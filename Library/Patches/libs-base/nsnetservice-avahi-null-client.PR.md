With the Avahi backend (GS_USE_AVAHI), an application aborts with `client.c:785: avahi_client_get_state: Assertion 'client' failed` when avahi-daemon or the system D-Bus cannot be reached: the client is NULL then, and `-[GSAvahiNetServiceBrowser canSearch]`, `-[GSAvahiNetService resolveWithTimeout:]` and `-startMonitoringForRecordType:` hand it to avahi anyway.

Reproducer: the new `Tests/base/NSNetService/noDaemon.m` sets `DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent`, then searches for and resolves a service. Run with `gnustep-tests noDaemon.m`, libgnustep-base built from master and from this branch:
```
master:  noDaemon: client.c:785: avahi_client_get_state: Assertion `client' failed.
         Failed file:  noDaemon.m aborted without running all tests!
branch:  2 Passed tests
         All OK!
```
`resolve.m` in the same directory still passes with the branch (34 tests). Only the resolve and search paths are covered by the test; the monitoring path gets the same guard but is not exercised by it.

The three methods now report AVAHI_ERR_NO_DAEMON through the normal didNotSearch, didNotResolve and didNotMonitor path when the client is NULL.

cc @pkgdemon
