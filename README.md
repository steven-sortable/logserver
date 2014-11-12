logserver - A server that logs POSTs
====================================

This is a simple HTTP server which appends all data POSTed to a fixed file.
To build, do

    cabal install --only-dependencies
    cabal configure
    cabal build

Then, to try it out, run

    dist/build/logserver/logserver 3042 mylogfile &
    tail -f mylogfile

and then, in another terminal window,

    echo "log entry" | ./log

This server is really just an exercise; it has obvious security weaknesses.
To partially mitigate them, it is hard-coded to listen only on 127.0.0.1.

The script [`greaselog.js`][1] is a [GreaseMonkey][2] script which,
on request, logs the title and URL of the current Firefox window in
markdown syntax.

 [1]: greaselog.js
 [2]: http://wiki.greasespot.net/Main_Page
