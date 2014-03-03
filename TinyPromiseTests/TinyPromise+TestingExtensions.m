#import "TinyPromise+TestingExtensions.h"

@implementation TinyPromise (TestingExtensions)

static BOOL _testMode = NO;

- (BOOL) testMode
{
  return _testMode;
}

- (void) setTestMode: (BOOL)mode
{
  _testMode = mode;
}

@end
