#import "TinyPromiseTests.h"
#import "TinyPromise+TestingExtensions.h"

#define kOneSecond 1000000000

@implementation TinyPromiseTests

- (void) setUp
{
  self.testSemaphore  = dispatch_semaphore_create(0);
  self.p1             = TinyPromise.new;
  self.p2             = TinyPromise.new;
  self.p3             = TinyPromise.new;
  
  self.p1.testMode    = YES;
  self.p2.testMode    = YES;
  self.p3.testMode    = YES;
}

/* --- */

- (void) tearDown
{
  self.testSemaphore  = nil;
  
  self.p1             = nil;
  self.p2             = nil;
  self.p3             = nil;
}

/* --- */

- (void) testInstantiation
{
  TinyPromise *p1 = nil;
  STAssertNoThrow(p1 = TinyPromise.new, @"Instantiation should not throw");
  STAssertNotNil(p1, @"New instance should not be nil");
}

/* --- */

- (void) testSinglePrematureDestruction
{
  TinyPromise         *p1          = TinyPromise.new;
  __block NSUInteger  doneCount    = 0;
  __block NSUInteger  failCount    = 0;
  __block NSUInteger  alwaysCount  = 0;
  
  p1.done(^(TinyPromise *p)
  {
   doneCount++;
   dispatch_semaphore_signal(self.testSemaphore);
  });
  
  p1.fail(^(TinyPromise *p)
  {
   failCount++;
   dispatch_semaphore_signal(self.testSemaphore);
  });
  
  p1.always(^(TinyPromise *p)
  {
   alwaysCount++;
   dispatch_semaphore_signal(self.testSemaphore);
  });

  [p1 destroy];
  
  NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
  STAssertTrue(doneCount == 0, @"doneCount should not have changed.");
  STAssertTrue(failCount == 0, @"failCount should not have changed.");
  STAssertTrue(alwaysCount == 0, @"alwaysCount should not have changed.");
}

/* --- */

- (void) testCompositePrematureDestructionOfParent
{
  TinyPromise         *m1           = [TinyPromise when:@[self.p1, self.p2, self.p3]];
  __block NSArray     *results      = nil;
  
  __block NSUInteger  doneCount     = 0;
  __block NSUInteger  failCount     = 0;
  __block NSUInteger  alwaysCount   = 0;
  
  m1.done(^(NSArray *ps)
  {
    doneCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.fail(^(NSArray *ps)
  {
    failCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.always(^(NSArray *ps)
  {
    alwaysCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  //Yank the rug out from under everything
  [m1 destroy];
  m1 = nil;
  
  //Then act like nothing happened
  [self.p1 resolveWith:[NSNumber numberWithBool:YES]];
  [self.p2 resolveWith:[NSNumber numberWithBool:YES]];
  [self.p3 resolveWith:[NSNumber numberWithBool:YES]];
  
  if ( !dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, kOneSecond)) )
  {
    STFail(@"Multiple resolution succeeded after composite promise was deleted");
  }
  else
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertFalse(doneCount, @"Done callback should not have executed.");
    STAssertFalse(failCount, @"Fail callback should not have executed.");
    STAssertFalse(alwaysCount, @"Always callback should not have executed.");
    
    STAssertNil(results, @"Results array should be nil.");
  }
}

/* --- */

- (void) testCompositePrematureDestructionOfChild
{  
  TinyPromise *m1                 = [TinyPromise when:@[self.p1, self.p2, self.p3]];
  __block NSArray *results        = nil;
  __block NSUInteger doneCount    = 0;
  __block NSUInteger failCount    = 0;
  __block NSUInteger alwaysCount  = 0;
  
  m1.done(^(NSArray *ps)
  {
    doneCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.fail(^(NSArray *ps)
  {
    failCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.always(^(NSArray *ps)
  {
    alwaysCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  [self.p1 resolveWith:[NSNumber numberWithBool:YES]];
  
  //Yoink!
  [self.p2 destroy];
  self.p2 = nil;
  
  [self.p3 resolveWith:[NSNumber numberWithBool:YES]];
  
  if ( dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, kOneSecond)) )
  {
    STFail(@"Multiple resolution timed out");
  }
  else
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertEquals(m1.state, kTinyPromiseStateResolved, @"State should be 'resolved'");
    STAssertTrue(doneCount, @"Done callback should have executed.");
    STAssertFalse(failCount, @"Fail callback should not have executed.");
    STAssertTrue(alwaysCount, @"Always callback should have executed.");
    
    STAssertNotNil(results, @"Results array should not be nil.");
    STAssertTrue([[results objectAtIndex:0] boolValue], @"First result should have been YES");
    STAssertTrue([[results objectAtIndex:1] isEqualToString:@"Dead Promise"], @"Second result should have been 'Dead Promise'");
    STAssertTrue([[results objectAtIndex:2] boolValue], @"Third result should have been YES");
  }
}

/* --- */

- (void) testSingleResolution
{
  __block NSUInteger doneCount    = 0;
  __block NSUInteger failCount    = 0;
  __block NSUInteger alwaysCount  = 0;
  
  self.p1.done(^(TinyPromise *p)
  {
    doneCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.done(^(TinyPromise *p)
  {
   doneCount++;
   dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.fail(^(TinyPromise *p)
  {
    failCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.always(^(TinyPromise *p)
  {
    alwaysCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.always(^(TinyPromise *p)
  {
    alwaysCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  [self.p1 resolveWith:[NSNumber numberWithBool:YES]];
  
  if ( dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, kOneSecond)) )
  {
    STFail(@"Resolution timed out.");
  }
  else
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertEquals(self.p1.state, kTinyPromiseStateResolved, @"State should be 'resolved'");
    STAssertTrue(doneCount == 2, @"Both done callbacks should have executed.");
    STAssertFalse(failCount, @"Fail callback should not have executed.");
    STAssertTrue(alwaysCount == 2, @"Both always callbacks should have executed.");
  }
}

/* --- */

- (void) testSingleRejection
{
  __block NSUInteger doneCount    = 0;
  __block NSUInteger failCount    = 0;
  __block NSUInteger alwaysCount  = 0;
  
  self.p1.done(^(TinyPromise *p)
  {
    doneCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.fail(^(TinyPromise *p)
  {
    failCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.fail(^(TinyPromise *p)
  {
    failCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.always(^(TinyPromise *p)
  {
    alwaysCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  self.p1.always(^(TinyPromise *p)
  {
    alwaysCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  [self.p1 rejectWith:[NSNumber numberWithBool:YES]];
  
  if ( dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, kOneSecond)) )
  {
    STFail(@"Rejection timed out.");
  }
  else
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertEquals(self.p1.state, kTinyPromiseStateRejected, @"State should be 'rejected'");
    STAssertFalse(doneCount, @"Done callback should not have executed.");
    STAssertTrue(failCount == 2, @"Both fail callbacks should have executed.");
    STAssertTrue(alwaysCount == 2, @"Both always callbacks should have executed.");
  }
}

/* --- */

- (void) testMultipleResolution
{
  TinyPromise         *m1           = [TinyPromise when:@[self.p1, self.p2, self.p3]];
  __block NSArray     *results      = nil;
  __block NSUInteger  doneCount     = 0;
  __block NSUInteger  failCount     = 0;
  __block NSUInteger  alwaysCount   = 0;

  m1.done(^(NSArray *ps)
  {
    doneCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.fail(^(NSArray *ps)
  {
    failCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.always(^(NSArray *ps)
  {
    alwaysCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  [self.p1 resolveWith:[NSNumber numberWithBool:YES]];
  [self.p2 resolveWith:[NSNumber numberWithBool:YES]];
  [self.p3 resolveWith:[NSNumber numberWithBool:YES]];
  
  if ( dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, kOneSecond)) )
  {
    STFail(@"Multiple resolution timed out");
  }
  else
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertEquals(m1.state, kTinyPromiseStateResolved, @"State should be 'resolved'");
    STAssertTrue(doneCount, @"Done callback should have executed.");
    STAssertFalse(failCount, @"Fail callback should not have executed.");
    STAssertTrue(alwaysCount, @"Always callback should have executed.");
    
    STAssertNotNil(results, @"Results array should not be nil.");
    STAssertTrue([[results objectAtIndex:0] boolValue], @"First result should have been YES");
    STAssertTrue([[results objectAtIndex:1] boolValue], @"Second result should have been YES");
    STAssertTrue([[results objectAtIndex:2] boolValue], @"Third result should have been YES");
  }
}

/* --- */

- (void) testMultipleRejection
{
  TinyPromise         *m1           = [TinyPromise when:@[self.p1, self.p2, self.p3]];
  __block NSArray     *results      = nil;
  __block NSUInteger  doneCount     = 0;
  __block NSUInteger  failCount     = 0;
  __block NSUInteger  alwaysCount   = 0;
  
  m1.done(^(NSArray *ps)
  {
    doneCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.fail(^(NSArray *ps)
  {
    failCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.always(^(NSArray *ps)
  {
    alwaysCount++;
    STAssertNotNil(ps, @"Completed promises array should not be nil.");
    results   = [ps valueForKeyPath:@"result"];
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  [self.p1 resolveWith:[NSNumber numberWithBool:YES]];
  [self.p2 rejectWith:[NSNumber numberWithBool:NO]]; //ANY rejection should result in rejection of the composite promise
  [self.p3 resolveWith:[NSNumber numberWithBool:YES]];
  
  if ( dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, kOneSecond)) )
  {
    STFail(@"Multiple rejection timed out.");
  }
  else
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertEquals(m1.state, kTinyPromiseStateRejected, @"State should be 'rejected'");
    STAssertFalse(doneCount, @"Done callback should not have executed.");
    STAssertTrue(failCount, @"Fail callback should have executed.");
    STAssertTrue(alwaysCount, @"Always callback should have executed.");
    
    STAssertNotNil(results, @"Results array should not be nil.");
    STAssertTrue([[results objectAtIndex:0] boolValue], @"First result should have been YES");
    STAssertFalse([[results objectAtIndex:1] boolValue], @"Second result should have been NO");
    STAssertTrue([[results objectAtIndex:2] boolValue], @"Third result should have been YES");
  }
}

/* --- */

- (void) testMultipleRunaway
{
  TinyPromise *m1                 = [TinyPromise when:@[self.p1, self.p2, self.p3]];
  __block NSUInteger doneCount    = 0;
  __block NSUInteger failCount    = 0;
  __block NSUInteger alwaysCount  = 0;

  m1.done(^(TinyPromise *p)
  {
    doneCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.fail(^(TinyPromise *p)
  {
    failCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  m1.always(^(TinyPromise *p)
  {
    alwaysCount++;
    dispatch_semaphore_signal(self.testSemaphore);
  });
  
  [self.p1 resolveWith:[NSNumber numberWithBool:YES]];
  //[p2 rejectWith:[NSNumber numberWithBool:YES]];
  [self.p3 resolveWith:[NSNumber numberWithBool:YES]];
  
  if ( dispatch_semaphore_wait(self.testSemaphore, dispatch_time(DISPATCH_TIME_NOW, 100)) )
  {
    NSLog(@"doneCount: %d failCount: %d alwaysCount: %d", (int)doneCount, (int)failCount, (int)alwaysCount);
    STAssertEquals(m1.state, kTinyPromiseStatePending, @"State should be 'pending'");
    STAssertFalse(doneCount, @"Done callback should not have executed.");
    STAssertFalse(failCount, @"Fail callback should not have executed.");
    STAssertFalse(alwaysCount, @"Always callback should not have executed.");
  }
  else
  {
    STFail(@"Runaway DIDN'T time out!");
  }
}

/* --- */

@end
