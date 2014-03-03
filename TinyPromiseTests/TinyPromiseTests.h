#import <SenTestingKit/SenTestingKit.h>

@class TinyPromise;

@interface TinyPromiseTests : SenTestCase

@property dispatch_semaphore_t          testSemaphore;
@property TinyPromise                   *p1;
@property TinyPromise                   *p2;
@property TinyPromise                   *p3;

@end
