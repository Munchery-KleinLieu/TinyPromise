#import <Foundation/Foundation.h>

typedef enum
{
  kTinyPromiseStateUnknown,
  kTinyPromiseStatePending,
  kTinyPromiseStateResolved,
  kTinyPromiseStateRejected,
  kTinyPromiseStateDying
  
} TinyPromiseState;

typedef void (^ TinyPromiseCompletion)(id p);
typedef void (^ TinyPromiseImmediate)(TinyPromiseCompletion);

@interface TinyPromise : NSObject
@property (readonly) TinyPromiseState                   state;
@property (nonatomic) id                                result;
@property (nonatomic) id                                identifier;

@property (readonly) BOOL                               isPending;
@property (readonly) BOOL                               isResolved;
@property (readonly) BOOL                               isRejected;

@property (nonatomic, readonly) TinyPromiseImmediate    always;
@property (nonatomic, readonly) TinyPromiseImmediate    done;
@property (nonatomic, readonly) TinyPromiseImmediate    fail;
@property (nonatomic, readonly) TinyPromiseImmediate    death;

+ (TinyPromise*) promiseWithIdentifier: (id)identifier;
+ (TinyPromise*) when: (NSArray*)promises;

- (TinyPromise*) initWithIdentifier: (id)identifier;
- (void) resolveWith: (id)result;
- (void) rejectWith: (id)result;
- (void) reset;
- (void) destroy;
@end

#define TracerPromise [TinyPromise promiseWithIdentifier: [NSString stringWithFormat: @"%@::%@ LINE %d", NSStringFromClass([self class]), NSStringFromSelector(_cmd), __LINE__]]

