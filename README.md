<p align="center">通</p>
=

TinyPromise
=
Promises are a way of life in **JavaScript** as they make contending with its ubiquitous asynchronous operations a great deal less horrible by giving two or more disparate entities a generic, lightweight means of informing one another when they're "done" doing something without knowing or caring whether or not the other one even exists. 

**iOS** applications are similar to **JavaScript** applications in that they almost always need to talk to remote services in order to do anything meaningful and there's a lot of frilly animation all over the place that you have to wait around on. Sadly, **Apple** doesn't supply developers with anything like **jQuery**'s `$Deferred` so the vast majority of us end up with elaborate delegate protocol definitions and notification name constants that are only used once, swaths of redundant boolean semaphore properties, sprawling nests of network callbacks coupling directly to front-endy things they probably should not, or lots of random mystery crashes caused by probabalistic race conditions like this:
```
Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 
'Could not find a view controller to execute unwinding for <MyDumbViewController: 0xf78ce11>'
```
and this:
```
'Unbalanced calls to begin/end appearance transitions for <MyDumbViewController>' 
```
*"Just don't flip the pages so fast!"*

### A Dismal Scene

While there are a handful of promise implementations for **Objective-C** out there, they're all pretty tough to read, even tougher to debug, and they generally have a ton of problems compiling under **ARC**. There's also **ReactiveCocoa**, but looking at the convoluted message pyramids they encourage you to litter your code with makes me hate life almost as much as the official Mac **GitHub** client for which it was written. 

**TinyPromise** takes a (perhaps overly) naive approach in vending the most useful features of `$Deferred` via some pretty straightforward **GCD** design patterns without worrying about too much of the other metaprogramming magic found in other libraries. This is probably ["missing the point,"](http://domenic.me/2012/10/14/youre-missing-the-point-of-promises/) but I've worked on some **Node** projects and theirs is honestly a point I'm happy missing. 

At its heart, **TinyPromise** is just a group of suspended operation queues with some syntactic sugar on top. It is **NOT** a full-blown implementation of the **Promises/A** spec or anything like that. These well-meaning specifications' lofty ideals quickly become incredibly annoying when translated to a strongly-typed language with an arcane and indecipherable block syntax, and I've just never had much personal need for the "thenable" construct myself.

### But... AFNetworking Has CALLBACKS!

Sure it does. Can you register more than one callback per operation? Can you refrain from invoking those callbacks when contending with potentially recoverable errors--like auth token expiration? Will it invoke your callback immediately if a particular operation has already completed before you got around to asking? Can you get it to invoke one specific callback after multiple concurrent operations have completed? Can it be used to notify you when an embed segue's run or a transition has completed? 

You probably can do most of those things somehow, but your code will be an unreadable mess. If you like to keep things stuck in 1988 the way Apple does, go nuts. It all compiles down to the same thing eventually.

Caveats
=
* **ARC** is *required*. I'm not doing the legacy macro thing. Sorry. 
* I've never built it for anything older than **iOS 6**.
* Serial chains of promises defined via `.` operators or `then` methods are not directly supported. 
* The tests are pretty ghetto as this antiquated **SenTest** thing doesn't really support asynchronous anything. 

Usage Examples:
=

Note that all completion blocks are invoked on the main thread, so it should be safe to muck with your UI within them. You should not assume that any particular completion block will execute before any other completion block.

#### Waiting for a single operation to succeed via `done`

```Objective-C
  #import <TinyPromise/TinyPromise.h>

  TinyPromise *p1         = TinyPromise.new;
  
  p1.done(^(TinyPromise *completed)
  {
    //This will run after p1 has been resolved.
    NSLog(@"%@", completed.result); // -> "All done!"
  });
  
  [p1 resolveWith:@"All done!"];
```

#### Waiting for a single operation to fail via `fail`

```Objective-C
  #import <TinyPromise/TinyPromise.h>

  TinyPromise *p1         = TinyPromise.new;
  
  p1.fail(^(TinyPromise *completed)
  {
    //This will run after p1 has been rejected.
    NSLog(@"%@", completed.result); // -> "Something blew up!"
  });
  
  [p1 rejectWith:@"Something blew up!"];
```

#### Waiting for a single operation to complete via `always`

```Objective-C
  #import <TinyPromise/TinyPromise.h>

  TinyPromise *p1         = TinyPromise.new;
  
  p1.always(^(TinyPromise *completed)
  {
    //This will run after p1 has been resolved OR rejected.
    if ( p1.state == kTinyPromiseStateResolved )
    {
      //Success code
    }
    else if ( p1.state == kTinyPromiseStateRejected )
    {
      //Failure code
    }
  });

  [p1 resolveWith:@"I don't care if this worked or not!"];
```

#### Waiting for multiple concurrent operations to complete via `when`:

If one promise rejects, the promise returned by `when` will be rejected as well, however, it *will* wait for them *all* to complete before resolving.

Note that the parameter passed to your completion handlers will be an `NSArray` of promises in this case.

```Objective-C
  #import <TinyPromise/TinyPromise.h>

  TinyPromise *p1         = TinyPromise.new;
  TinyPromise *p2         = TinyPromise.new;
  TinyPromise *p3         = TinyPromise.new;
  
  [TinyPromise when:@[p1, p2, p3]].always(^(NSArray *promises)
  {
    //This will run only after all three promises have been resolved or rejected.
    NSArray *results = [promises valueForKeyPath:@"result"];
    NSLog(@"%@ %@ %@", [results objectAtIndex:0], [results objectAtIndex:1], [results objectAtIndex:2]);
  });
  
  [p1 resolveWith:@"Any"];
  [p2 resolveWith:@"Object"];
  [p3 resolveWith:@"Will Do"];
```
