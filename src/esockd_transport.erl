%%%===================================================================
%%% Copyright (c) 2013-2018 EMQ Inc. All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%===================================================================

-module(esockd_transport).

-author("Feng Lee <feng@emqtt.io>").

-include("esockd.hrl").

-export([type/1, is_ssl/1]).
-export([listen/2]).
-export([ready/3, wait/1]).
-export([send/2, async_send/2, recv/2, recv/3, async_recv/2, async_recv/3]).
-export([controlling_process/2]).
-export([close/1, fast_close/1]).
-export([getopts/2, setopts/2, getstat/2]).
-export([sockname/1, peername/1, shutdown/2]).
-export([peercert/1, peer_cert_subject/1, peer_cert_common_name/1]).
-export([ssl_upgrade_fun/1]).
-export([proxy_upgrade_fun/1]).
-export([ensure_ok_or_exit/2]).
-export([gc/1]).

-type(ssl_socket() :: #ssl_socket{}).
-type(proxy_socket() :: #proxy_socket{}).
-type(sock() :: inet:socket() | ssl_socket() | proxy_socket()).
-export_type([sock/0]).

-spec(type(sock()) -> tcp | ssl | proxy).
type(Sock) when is_port(Sock) ->
    tcp;
type(#ssl_socket{ssl = _SslSock})  ->
    ssl;
type(#proxy_socket{}) ->
    proxy.

-spec(is_ssl(sock()) -> boolean()).
is_ssl(Sock) when is_port(Sock) ->
    false;
is_ssl(#ssl_socket{})  ->
    true;
is_ssl(#proxy_socket{socket = Sock}) ->
    is_ssl(Sock).

-spec(ready(pid(), sock(), [esockd:sock_fun()]) -> any()).
ready(Pid, Sock, UpgradeFuns) ->
    Pid ! {sock_ready, Sock, UpgradeFuns}.

-spec(wait(sock()) -> {ok, sock()} | {error, term()}).
wait(Sock) ->
    receive
        {sock_ready, Sock, UpgradeFuns} ->
            upgrade(Sock, UpgradeFuns)
    end.

-spec(upgrade(sock(), [esockd:sock_fun()]) -> {ok, sock()} | {error, term()}).
upgrade(Sock, []) ->
    {ok, Sock};
upgrade(Sock, [Upgrade | More]) ->
    case Upgrade(Sock) of
        {ok, NewSock} -> upgrade(NewSock, More);
        Error         -> fast_close(Sock), Error
    end.

-spec(listen(inet:port_number(), [gen_tcp:listen_option()])
      -> {ok, inet:socket()} | {error, system_limit | inet:posix()}).
listen(Port, Options) ->
    gen_tcp:listen(Port, Options).

-spec(controlling_process(sock(), pid()) -> ok | {error, Reason} when
    Reason :: closed | not_owner | badarg | inet:posix()).
controlling_process(Sock, NewOwner) when is_port(Sock) ->
    gen_tcp:controlling_process(Sock, NewOwner);
controlling_process(#ssl_socket{ssl = SslSock}, NewOwner) ->
    ssl:controlling_process(SslSock, NewOwner).

-spec(close(sock()) -> ok).
close(Sock) when is_port(Sock) ->
    gen_tcp:close(Sock);
close(#ssl_socket{ssl = SslSock}) ->
    ssl:close(SslSock);
close(#proxy_socket{socket = Sock}) ->
    close(Sock).

-spec(fast_close(sock()) -> ok).
fast_close(Sock) when is_port(Sock) ->
    catch port_close(Sock), ok;
fast_close(#ssl_socket{tcp = Sock, ssl = SslSock}) ->
    {Pid, MRef} = spawn_monitor(fun() -> ssl:close(SslSock) end),
    erlang:send_after(?SSL_CLOSE_TIMEOUT, self(), {Pid, ssl_close_timeout}),
    receive
        {Pid, ssl_close_timeout} ->
            erlang:demonitor(MRef, [flush]),
            exit(Pid, kill);
        {'DOWN', MRef, process, Pid, _Reason} ->
            ok
    end,
    catch port_close(Sock), ok;
fast_close(#proxy_socket{socket = Sock}) ->
    fast_close(Sock).

-spec(send(sock(), iodata()) -> ok | {error, Reason} when
    Reason :: closed | timeout | inet:posix()).
send(Sock, Data) when is_port(Sock) ->
    gen_tcp:send(Sock, Data);
send(#ssl_socket{ssl = SslSock}, Data) ->
    ssl:send(SslSock, Data);
send(#proxy_socket{socket = Sock}, Data) ->
    send(Sock, Data).

%% @doc Port command to write data.
-spec(async_send(sock(), iodata()) -> ok | {error, Reason} when
    Reason :: close | timeout | inet:posix()).
async_send(Sock, Data) when is_port(Sock) ->
    case erlang:port_command(Sock, Data, [nosuspend]) of
        true  -> ok;
        false -> {error, timeout} %% TODO: tcp window full?
    end;
async_send(Sock = #ssl_socket{ssl = SslSock}, Data) ->
    case ssl:send(SslSock, Data) of
        ok -> self() ! {inet_reply, Sock, ok}, ok;
        {error, Reason} -> {error, Reason}
    end;
async_send(#proxy_socket{socket = Sock}, Data) ->
    async_send(Sock, Data).

-spec(recv(sock(), non_neg_integer()) ->
    {ok, iodata()} | {error, closed | inet:posix()}).
recv(Sock, Length) when is_port(Sock) ->
    gen_tcp:recv(Sock, Length);
recv(#ssl_socket{ssl = SslSock}, Length) ->
    ssl:recv(SslSock, Length);
recv(#proxy_socket{socket = Sock}, Length) ->
    recv(Sock, Length).

-spec(recv(sock(), non_neg_integer(), timeout()) ->
    {ok, iodata()} | {error, closed | inet:posix()}).
recv(Sock, Length, Timeout) when is_port(Sock) ->
    gen_tcp:recv(Sock, Length, Timeout);
recv(#ssl_socket{ssl = SslSock}, Length, Timeout)  ->
    ssl:recv(SslSock, Length, Timeout);
recv(#proxy_socket{socket = Sock}, Length, Timeout) ->
    recv(Sock, Length, Timeout).

%% @doc Async receive data.
-spec(async_recv(sock(), non_neg_integer()) -> {ok, reference()}).
async_recv(Sock, Length) ->
    async_recv(Sock, Length, infinity).

-spec(async_recv(sock(), non_neg_integer(), timeout()) -> {ok, reference()}).
async_recv(Sock = #ssl_socket{ssl = SslSock}, Length, Timeout) ->
    Self = self(),
    Ref = make_ref(),
    spawn(fun() ->
              Self ! {inet_async, Sock, Ref,
                      ssl:recv(SslSock, Length, Timeout)}
          end),
    {ok, Ref};
async_recv(Sock, Length, infinity) when is_port(Sock) ->
    prim_inet:async_recv(Sock, Length, -1);
async_recv(Sock, Length, Timeout) when is_port(Sock) ->
    prim_inet:async_recv(Sock, Length, Timeout);
async_recv(#proxy_socket{socket = Sock}, Length, Timeout) ->
    async_recv(Sock, Length, Timeout).

%% @doc Get socket options.
-spec(getopts(sock(), [inet:socket_getopt()]) ->
    {ok, [inet:socket_setopt()]} | {error, inet:posix()}).
getopts(Sock, OptionNames) when is_port(Sock) ->
    inet:getopts(Sock, OptionNames);
getopts(#ssl_socket{ssl = SslSock}, OptionNames) ->
    ssl:getopts(SslSock, OptionNames);
getopts(#proxy_socket{socket = Sock}, OptionNames) ->
    getopts(Sock, OptionNames).

%% @doc Set socket options
-spec(setopts(sock(), [inet:socket_setopt()]) -> ok | {error, inet:posix()}).
setopts(Sock, Options) when is_port(Sock) ->
    inet:setopts(Sock, Options);
setopts(#ssl_socket{ssl = SslSock}, Options) ->
    ssl:setopts(SslSock, Options);
setopts(#proxy_socket{socket = Socket}, Options) ->
    setopts(Socket, Options).

%% @doc Get socket stats
-spec(getstat(sock(), [inet:stat_option()]) ->
    {ok, [{inet:stat_option(), integer()}]} | {error, inet:posix()}).
getstat(Sock, Stats) when is_port(Sock) ->
    inet:getstat(Sock, Stats);
getstat(#ssl_socket{tcp = Sock}, Stats) ->
    inet:getstat(Sock, Stats);
getstat(#proxy_socket{socket = Sock}, Stats) ->
    getstat(Sock, Stats).

%% @doc Sockname
-spec(sockname(sock()) -> {ok, {inet:ip_address(), inet:port_number()}} |
                          {error, inet:posix()}).
sockname(Sock) when is_port(Sock) ->
    inet:sockname(Sock);
sockname(#ssl_socket{ssl = SslSock}) ->
    ssl:sockname(SslSock);
sockname(#proxy_socket{dst_addr = DstAddr, dst_port = DstPort}) ->
    {ok, {DstAddr, DstPort}}.

%% @doc Peername
-spec(peername(sock()) -> {ok, {inet:ip_address(), inet:port_number()}} |
                          {error, inet:posix()}).
peername(Sock) when is_port(Sock) ->
    inet:peername(Sock);
peername(#ssl_socket{ssl = SslSock}) ->
    ssl:peername(SslSock);
peername(#proxy_socket{src_addr = SrcAddr, src_port = SrcPort}) ->
    {ok, {SrcAddr, SrcPort}}.

%% @doc Socket peercert
-spec(peercert(sock()) -> nossl | {ok, Cert :: binary()} | {error, term()}).
peercert(Sock) when is_port(Sock) ->
    nossl;
peercert(#ssl_socket{ssl = SslSock}) ->
    ssl:peercert(SslSock);
peercert(#proxy_socket{socket = Sock}) ->
    ssl:peercert(Sock).

%% @doc Peercert subject
-spec(peer_cert_subject(sock()) -> undefined | binary()).
peer_cert_subject(Sock) when is_port(Sock) ->
    undefined;
peer_cert_subject(#ssl_socket{ssl = SslSock}) ->
    esockd_ssl:peer_cert_subject(ssl:peercert(SslSock));
peer_cert_subject(Sock) when ?IS_PROXY(Sock) ->
    %% Common Name? PP2 will not pass subject.
    peer_cert_common_name(Sock).

%% @doc Peercert common name
-spec(peer_cert_common_name(sock()) -> undefined | binary()).
peer_cert_common_name(Sock) when is_port(Sock) ->
    undefined;
peer_cert_common_name(#ssl_socket{ssl = SslSock}) ->
    esockd_ssl:peer_cert_common_name(ssl:peercert(SslSock));
peer_cert_common_name(#proxy_socket{pp2_additional_info = AdditionalInfo}) ->
    SslInfo = proplists:get_value(pp2_ssl, AdditionalInfo, []),
    proplists:get_value(pp2_ssl_cn, SslInfo).

%% @doc Shutdown socket
-spec(shutdown(sock(), How) -> ok | {error, inet:posix()} when
    How :: read | write | read_write).
shutdown(Sock, How) when is_port(Sock) ->
    gen_tcp:shutdown(Sock, How);
shutdown(#ssl_socket{ssl = SslSock}, How) ->
    ssl:shutdown(SslSock, How);
shutdown(#proxy_socket{socket = Sock}, How) ->
    shutdown(Sock, How).

%% TCP -> SslSocket
ssl_upgrade_fun(SslOpts) ->
    Timeout = handshake_timeout(SslOpts),
    SslOpts1 = proplists:delete(handshake_timeout, SslOpts),
    fun(Sock) when is_port(Sock) ->
        case catch ssl:ssl_accept(Sock, SslOpts1, Timeout) of
            {ok, SslSock} ->
                {ok, #ssl_socket{tcp = Sock, ssl = SslSock}};
            {error, Reason} when Reason =:= closed;
                                 Reason =:= timeout ->
                {error, Reason};
            {error, {tls_alert, _}} ->
                {error, tls_alert};
            {error, Reason} ->
                {error, {ssl_error, Reason}};
            {'EXIT', Reason} ->
                {error, {ssl_failure, Reason}}
        end
    end.

handshake_timeout(SslOpts) ->
    proplists:get_value(handshake_timeout, SslOpts, ?SSL_HANDSHAKE_TIMEOUT).

%% TCP | SSL -> ProxySocket
proxy_upgrade_fun(Options) ->
    Timeout = proxy_protocol_timeout(Options),
    fun(Sock) ->
        case esockd_proxy_protocol:recv(?MODULE, Sock, Timeout) of
            {ok, ProxySock} -> {ok, ProxySock};
            {error, Reason} -> {error, Reason}
        end
    end.

proxy_protocol_timeout(Options) ->
    proplists:get_value(proxy_protocol_timeout, Options, ?PROXY_RECV_TIMEOUT).

ensure_ok_or_exit(Fun, Args) ->
    Sock = element(1, Args),
    case erlang:apply(?MODULE, Fun, Args) of
        {error, Reason} when Reason =:= enotconn;
                             Reason =:= closed ->
            fast_close(Sock),
            exit(normal);
        {error, Reason} ->
            fast_close(Sock),
            exit({shutdown, Reason});
         Result -> Result
    end.

gc(Sock) when is_port(Sock) ->
    ok;
%% Defined in ssl/src/ssl_api.hrl:
%% -record(sslsocket, {fd = nil, pid = nil}).
gc(#ssl_socket{ssl = {sslsocket, _, Pid}}) when is_pid(Pid) ->
    erlang:garbage_collect(Pid);
gc(#proxy_socket{socket = Sock}) ->
    gc(Sock);
gc(_Sock) ->
    ok.

