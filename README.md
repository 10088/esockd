# eSockd

Erlang General Non-blocking TCP Server

NOTICE: not production ready

## build

```
	make
```

## usage

test/esockd_test.erl:

```erlang
    esockd:start(),
    esockd:listen(5000, ?TCP_OPTIONS, {echo_server, start_link, []}).
```

## how to handle e{n,m}file errors when accept?

### error description

enfile: The system limit on the total number of open files has been reached.

emfile: The per-process limit of open file descriptors has been reached. "ulimit -n XXX"

### solution

acceptor sleep for a while.

## tune

ERL_MAX_PORTS: Erlang Ports Limit

ERTS_MAX_PORTS: 

+P: Maximum Number of Erlang Processes

+K true: Kernel Polling

The kernel polling option requires that you have support for it in your kernel. By default, Erlang currently supports kernel polling under FreeBSD, Mac OS X, and Solaris. If you use Linux, check this newspost. Additionaly, you need to enable this feature while compiling Erlang.

ERL_MAX_ETS_TABLES
