Title: Keep distributed notifications flowing when a client hangs or gdnc restarts

Three things leave every process of a session without distributed notifications. gdnc sends each notification synchronously and without a time limit, so one client that stops reading (hung, stopped, or dead while a child still holds its socket) blocks delivery to everybody, and each post that arrives meanwhile nests another wait on top of it. When gdnc runs as a daemon it closes descriptors 0, 1 and 2, so client connections get them and anything gdnc logs to stderr is written into a client's socket (the client then reports `bad data received on port handle, rType=842019382`, which is "2026", the start of the NSLog timestamp). And when gdnc is restarted, or drops a client, `-_invalidated:` only clears `_remote`: the next call reconnects and registers the client, but its earlier observers are never registered again, so a process that only observes stays deaf until it is restarted.

Reproducer: the tests in `Tests/base/NSDistributedNotificationCenter` re-execute themselves with a private `TEMP`/`TMP`, so they never touch the gdnc of the user running them, and run their own `gdnc --no-fork` (the one named by `GDNC`, else gdnc from PATH). `stuckClient.m` stops one client and floods it, then checks that a client connecting afterwards and the poster still get notifications. `serverRestart.m` kills gdnc, starts a new one and checks that an observer still gets a post from another process. `droppedClient.m` lets gdnc (client timeout 1 s) drop a stopped client and checks that it receives again after it resumes. Run with `GDNC=Tools/obj/gdnc gnustep-tests .`, library and gdnc built from master and from this branch:
```
master:  Failed test:  serverRestart.m:267 ... the observer gets a notification posted after the restart (0 within 10 s)
         Failed test:  stuckClient.m:401 ... a client that connects while one is stopped registers and gets a notification (status -1 after 30.0 s)
         Failed test:  stuckClient.m:403 ... the poster gets its marker
         Failed test:  stuckClient.m:406 ... every post reached the poster (0 of 201)
         11 passed, 4 failed
branch:  15 passed, 0 failed (5 runs out of 5)
```
`droppedClient.m` passes on master only because master never drops the client; with the gdnc changes but without the client changes it fails with "the dropped client gets a notification after it resumes". The NSConnection tests still pass (24 tests).

gdnc now queues notifications and sends them from one non-reentrant loop, gives each client connection a request timeout (5 s, the `GDNCClientTimeout` default overrides it) and drops a client that reads nothing for that long. It points its standard descriptors at /dev/null instead of closing them, as gdomap already does. The center keeps a record of what it registered with gdnc (observer, selector, name, object, suspension behaviour), forgets records in `-removeObserver:name:object:`, and registers them again with the suspension state whenever it connects. After the connection dies it reconnects from a timer on the main run loop, retrying with a growing delay (0.5 s up to 32 s) while gdnc cannot be reached. A process whose main run loop does not run reconnects lazily on its next call as before, and a center without observers does not reconnect by itself. The new instance variables go through GSInternal.

cc @pkgdemon
