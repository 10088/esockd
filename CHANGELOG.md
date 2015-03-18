
eSockd ChangeLog
==================

2.1.0-alpha (2015/03/18)
------------------------

esockd_connections_sup: do not user supervisor, write a new implematation

remove esockd_manager, merge its functions to the new esockd_connectioins_sup

esockd_acceptor: fix the tune buffer issue. when set buffer as max of sndbuf, recbuf, esockd will consume too much memories

esockd: add 'tune_buffer' option to tune 'buffer' for hight throughput socket

esockd_transport: add recv/3 function

Benchmark this release on one 8 cores, 32G memory ubuntu/14.04 server from QingCloud:

```
2500K concurrent connections, 50K messages/sec, 40Mbps In/Out Consumed 5G memory, 20% CPU/core
```


2.0.1-alpha (2015/03/15)
------------------------

esockd.app.src: update vsn to 2.0.1

update change logs


2.0.0-alpha (2015/03/15)
------------------------

Support [Allow/Deny](https://github.com/emqtt/esockd/wiki/Allow-and-Deny) features like NGINX.

esockd to add allow/2, deny/2, get_access_rules/1 APIs

esockd_manager to add allow/2, deny/2, access_rules/1 APIs

new esockd_access file


v1.2.0-beta (2015/03/13)
------------------------

rename 'acceptor_pool' option to 'acceptors'


v1.1.0-beta (2015/03/10)
------------------------

Make esockd_stats table public and write_concurrency

esockd_acceptor: fix format of Accept log


v1.0.0-beta (2015/03/03)
------------------------

First public release with stable API.


v0.3.0-beta (2015/03/03)
------------------------

esockd add close/1, get_acceptor_pool/1, get_stats/1 apis

esockd_acceptor_sup add count_acceptors/1 api

esockd_acceptor add 'statsfun' to state

esockd_net add format/2 api

esockd_listener_sup: change 'restart strategy' from one_for_all to rest_for_one

esockd.hrl: remove 'sock_args' record 

esockd_server add stats_fun/2, inc_stats/3, dec_stats/3, get_stats/1, del_stats/1


v0.2.0-beta (2015/03/02)
------------------------

esockd.erl: add get_max_clients/1, set_max_clients/2, get_current_clients/1

esockd_connection.erl: 'erlang:apply(M, F, [SockArgs|Args])'

esockd_acceptor.erl: log protocol name

gen_logger to replace error_logger, and support 'logger' option


0.1.1-beta (2015/03/01)
------------------------

Doc: update README.md


0.1.0-beta (2015/03/01)
------------------------

Add more exmaples

Add esockd_server.erl

Redesign esockd_manager.erl, esockd_connection_sup.erl


0.1.0-alpha (2015/02/28)
------------------------

First public release

TCP/SSL Socket Server


0.0.2 (2014/12/07)
------------------------

acceptor suspend 100ms when accept 'emfile' error

esockd_client_sup to control max connections

esockd_client_sup: 'M:go(Client, Sock)' to tell gen_server the socket is ready

esockd_acceptor: add 'tune_buffer_size'


0.0.1 (2014/11/30)
------------------------

redesign listener api

first release...


