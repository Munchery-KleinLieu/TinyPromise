#import "TinyPromise.h"

@interface TinyPromise ()
@property (nonatomic) dispatch_queue_t            mainQueue;
@property (nonatomic) dispatch_group_t            mainGroup;

//The resolution queue runs on resolution only
@property (nonatomic) dispatch_queue_t            resolutionQueue;
@property (atomic) UInt32                         resolutionManifest;

//The rejection queue runs on rejection only
@property (nonatomic) dispatch_queue_t            rejectionQueue;
@property (atomic) UInt32                         rejectionManifest;

//The always queue runs on resolution or rejection
@property (nonatomic) dispatch_queue_t            alwaysQueue;
@property (atomic) UInt32                         alwaysManifest;

//The death queue runs on resolution, rejection and destruction
@property (nonatomic) dispatch_queue_t            deathQueue;
@property (atomic) UInt32                         deathManifest;

@property (atomic) UInt32                         totalCompletionBlocksQueuedOverTime;
@property (atomic, readonly) UInt32               pendingCompletionBlocks;

@property BOOL                                    suspended;

@property NSArray*                                childPromises;

- (void) suspendQueues;
- (void) resumeQueues;
- (void) enqueueHandler: (TinyPromiseCompletion)handler in:(dispatch_queue_t)queue;
- (TinyPromiseImmediate) immediateBlockForQueue: (dispatch_queue_t)queue;
@end

@implementation TinyPromise

+ (TinyPromise*) promiseWithIdentifier: (id)identifier
{
  return [[TinyPromise alloc] initWithIdentifier: identifier];
}

/* --- */

+ (TinyPromise*) when:(NSArray*)promises
{
  __block TinyPromise *composite      = TracerPromise;
  __block dispatch_queue_t whenQueue  = dispatch_queue_create("tinypromise.when", DISPATCH_QUEUE_SERIAL);
  
  //Don't let these die as long as we're waiting on them
  composite.childPromises = promises;
  
  for ( TinyPromise *promise in promises )
  {
    //If any of our constituents are in test mode
    //make sure the composite promise is, too.
    if ( [promise respondsToSelector:NSSelectorFromString(@"testMode")] )
      if ( [promise valueForKeyPath:@"testMode"] )
        [composite setValue:[NSNumber numberWithBool:YES] forKeyPath:@"testMode"];
    
    //Stack up suspensions
    dispatch_suspend(whenQueue);
    
    //Death is the only inevitability in a
    //promise's life cycle. We must not block
    //when one of them is deallocated out from
    //under us.
    promise.death(^ (id p)
    {
      //And knock them down as results come in
      dispatch_resume(whenQueue);
    });
  }
  
  //Insert a single task to be run once the final
  //resume goes through.
  dispatch_async(whenQueue, ^
  {
    BOOL shouldReject         = NO;
    NSMutableArray *results   = [NSMutableArray arrayWithCapacity:promises.count];
    
    for ( TinyPromise *promise in promises )
    {
      if ( promise.isRejected )
      {
        shouldReject = YES;
      }
      
      if ( promise.result )
        [results addObject:promise.result];
    }
    
    if ( shouldReject )
    {
      [composite rejectWith:results];
    }
    else
    {
      [composite resolveWith:results];
    }
  });
  
  return composite;
}

/* --- */

- (id) init
{
  self = [super init];
  
  if ( self )
  {
    //Never suspended. Enforce order: done -> fail -> always
    _mainQueue        = dispatch_queue_create("tinypromise.callbacks", DISPATCH_QUEUE_SERIAL);
    _mainGroup        = dispatch_group_create();
    
    //Suspended until resolved/rejected/destroyed. Absolutely no order whatsoever.
    _resolutionQueue  = dispatch_queue_create("tinypromise.resolution", DISPATCH_QUEUE_CONCURRENT);
    _rejectionQueue   = dispatch_queue_create("tinypromise.rejection", DISPATCH_QUEUE_CONCURRENT);
    _alwaysQueue      = dispatch_queue_create("tinypromise.always", DISPATCH_QUEUE_CONCURRENT);
    _deathQueue       = dispatch_queue_create("tinypromise.death", DISPATCH_QUEUE_CONCURRENT);
    
    _childPromises    = nil;
    
    [self reset];
  }
  return self;
}

/* --- */

- (id) initWithIdentifier: (id) identifier
{
  self = [self init];
  
  if ( self )
  {
    _identifier = identifier;
  }
  
  return self;
}

/* --- */

- (void) dealloc
{
  [self destroy];
}

/* --- */

- (void) destroy
{
  //If you let a suspended queue get
  //disposed you will crash. Open the
  //floodgates and let everything run
  //but refrain from actually invoking
  //any client callbacks. 
  _state = kTinyPromiseStateDying;
  
  if ( !self.result )
    self.result = @"Dead Promise";

  [self resumeQueues];
  
  //dispatch_group_wait is far from infallible when
  //blocks may be added and/or destroyed on different
  //threads. Only get GCD involved if it's genuinely
  //necessary to try and let something finish.
  if ( self.pendingCompletionBlocks || self.totalCompletionBlocksQueuedOverTime == 0 )
  {
    if ( dispatch_group_wait(self.mainGroup, dispatch_time(DISPATCH_TIME_NOW, 5000000000)) )
    {
      if ( self.pendingCompletionBlocks )
      {
        NSLog(@"Deallocating a TinyPromise with %d active jobs. You're probably going to crash. %@", (unsigned int)self.pendingCompletionBlocks, self.identifier ? self.identifier : self);
        //[NSException raise:@"TinyPromiseZombie" format:@"Deallocating a TinyPromise with %d active jobs. You're probably going to crash. %@", (unsigned int)self.pendingCompletionBlocks, self.identifier ? self.identifier : self];
      }
    }
  }
  
  if ( self.childPromises )
    self.childPromises = nil;
}

/* --- */

- (void) reset
{
  if ( self.state != kTinyPromiseStatePending )
  {
    [self suspendQueues];
    
    _state      = kTinyPromiseStatePending;
    self.result = nil;
  }
}

/* --- */

- (void) suspendQueues
{
  if ( !self.suspended )
  {
    if ( !dispatch_group_wait(self.mainGroup, dispatch_time(DISPATCH_TIME_NOW, 5000000000)) )
    {
      dispatch_suspend(self.resolutionQueue);
      dispatch_suspend(self.rejectionQueue);
      dispatch_suspend(self.alwaysQueue);
      dispatch_suspend(self.deathQueue);
      self.suspended = YES;
    }
    else
    {
      NSLog(@"Suspending a TinyPromise with active jobs.");
    }
  }
}

/* --- */

- (void) resumeQueues
{
  if ( self.suspended )
  {
    dispatch_group_async(self.mainGroup, self.mainQueue, ^{ dispatch_resume(self.resolutionQueue); });
    dispatch_group_async(self.mainGroup, self.mainQueue, ^{ dispatch_resume(self.rejectionQueue); });
    dispatch_group_async(self.mainGroup, self.mainQueue, ^{ dispatch_resume(self.alwaysQueue); });
    dispatch_group_async(self.mainGroup, self.mainQueue, ^{ dispatch_resume(self.deathQueue); });
    
    self.suspended = NO;
  }
}

/* --- */

- (BOOL) isPending
{
  return ( self.state == kTinyPromiseStatePending );
}

/* --- */

- (BOOL) isResolved
{
  return ( self.state == kTinyPromiseStateResolved );
}

/* --- */

- (BOOL) isRejected
{
  return ( self.state == kTinyPromiseStateRejected );
}

/* --- */

- (void) resolveWith:(id)result
{
  self.result = result;
  _state      = kTinyPromiseStateResolved;
  
  [self resumeQueues];
}

/* --- */

- (void) rejectWith:(id)result
{
  self.result = result;
  _state      = kTinyPromiseStateRejected;
  
  [self resumeQueues];
}

/* --- */

- (void) enqueueHandler: (TinyPromiseCompletion)handler in:(dispatch_queue_t)queue
{
  if ( queue == self.resolutionQueue ) self.resolutionManifest++;
  else if ( queue == self.rejectionQueue ) self.rejectionManifest++;
  else if ( queue == self.alwaysQueue ) self.alwaysManifest++;
  else if ( queue == self.deathQueue ) self.deathManifest++;
  
  self.totalCompletionBlocksQueuedOverTime++;
  
  dispatch_group_async(self.mainGroup, queue, ^
  {
    //There's no way to dequeue a block once it's been scheduled
    //so just refrain from invoking the handlers to simulate
    //cancelation.
    BOOL invokeHandler = YES;
    
    if ( self.state == kTinyPromiseStateUnknown )
    {
      invokeHandler = NO;
    }
    else
    {
      if ( queue == self.resolutionQueue && self.state != kTinyPromiseStateResolved )
       invokeHandler = NO;

      if ( queue == self.rejectionQueue && self.state != kTinyPromiseStateRejected )
       invokeHandler = NO;

      if ( queue == self.alwaysQueue && self.state != kTinyPromiseStateResolved && self.state != kTinyPromiseStateRejected )
       invokeHandler = NO;
      
      if ( queue == self.deathQueue && self.state < kTinyPromiseStateResolved )
        invokeHandler = NO;
    }
    
    if ( queue == self.resolutionQueue ) self.resolutionManifest--;
    else if ( queue == self.rejectionQueue ) self.rejectionManifest--;
    else if ( queue == self.alwaysQueue ) self.alwaysManifest--;
    else if ( queue == self.deathQueue ) self.deathManifest--;
    
    if ( invokeHandler )
    {
      void (^invoker)(void) = ^{ handler(self); };
      
      //dispatch_get_main_queue will hang a unit test
      BOOL runOnMainThread = YES;
      
      if ( [self respondsToSelector:NSSelectorFromString(@"testMode")] )
        runOnMainThread = ![[self valueForKeyPath:@"testMode"] boolValue];
      
      if ( runOnMainThread )
      {
        dispatch_async(dispatch_get_main_queue(), invoker);
      }
      else
      {
        invoker();
      }
    }
  });
}

/* --- */

- (UInt32) pendingCompletionBlocks
{
  return self.resolutionManifest + self.rejectionManifest + self.alwaysManifest + self.deathManifest;
}

/* --- */

- (TinyPromiseImmediate) immediateBlockForQueue: (dispatch_queue_t)queue
{
  return ^(TinyPromiseCompletion handler)
  {
    [self enqueueHandler:handler in:queue];
  };
}

/* --- */

- (TinyPromiseImmediate) always
{
  return [self immediateBlockForQueue: self.alwaysQueue];
}

/* --- */

- (TinyPromiseImmediate) done
{
  return [self immediateBlockForQueue: self.resolutionQueue];
}

/* --- */

- (TinyPromiseImmediate) fail
{
  return [self immediateBlockForQueue: self.rejectionQueue];
}

/* --- */

- (TinyPromiseImmediate) death
{
  return [self immediateBlockForQueue: self.deathQueue];
}

@end
