%%--------------------------------------------------------------------
%% Copyright (c) 2019 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(esockd_dtls_listener_sup).

-behaviour(supervisor).

-import(esockd_listener_sup,
        [ buffer_tune_fun/1
        , rate_limit_fun/2
        ]).

%% APIs
-export([ start_link/4
        , listener/1
        , acceptor_sup/1
        , connection_sup/1
        ]).

%% get/set
-export([ get_options/1
        , get_acceptors/1
        , get_max_connections/1
        , get_current_connections/1
        , get_shutdown_count/1
        ]).

-export([ set_max_connections/2 ]).

-export([ get_access_rules/1
        , allow/2
        , deny/2
        ]).

%% supervisor callbacks
-export([init/1]).

-define(ERROR_MSG(Format, Args),
        error_logger:error_msg("[~s]: " ++ Format, [?MODULE | Args])).

%%--------------------------------------------------------------------
%% APIs
%%--------------------------------------------------------------------

-spec(start_link(atom(), esockd:listen_on(),
                 [esockd:option()], mfa()) -> {ok, pid()} | {error, term()}).
start_link(Proto, ListenOn, Opts, MFA) ->
    {ok, Sup} = supervisor:start_link(?MODULE, []),
    %% Start connection sup
    %%
    %% !!! IMPORTANT: It's same as tcp/ssl `esockd_connection_sup`
    ConnSupSpec = #{id => connection_sup,
                    start => {esockd_connection_sup, start_link, [Opts, MFA]},
                    restart => transient,
                    shutdown => infinity,
                    type => supervisor,
                    modules => [esockd_connection_sup]},
    {ok, ConnSup} = supervisor:start_child(Sup, ConnSupSpec),

    %% State acceptor sup
    TuneFun = buffer_tune_fun(Opts),
    UpgradeFuns = upgrade_funs(Opts),
    StatsFun = esockd_server:stats_fun({Proto, ListenOn}, accepted),
    LimitFun = rate_limit_fun({listener, Proto, ListenOn}, Opts),
    AcceptorSupSpec = #{id => acceptor_sup,
                        start => {esockd_dtls_acceptor_sup, start_link,
                                  [ConnSup, TuneFun, UpgradeFuns, StatsFun, LimitFun]},
                        restart => transient,
                        shutdown => infinity,
                        type => supervisor,
                        modules => [esockd_dtls_acceptor_sup]},
    {ok, AcceptorSup} = supervisor:start_child(Sup, AcceptorSupSpec),
    %% Start listener
    ListenerSpec = #{id => listener,
                     start => {esockd_dtls_listener, start_link,
                               [Proto, ListenOn, Opts, AcceptorSup]},
                     restart => transient,
                     shutdown => 16#ffffffff,
                     type => worker,
                     modules => [esockd_dtls_listener]},
    case supervisor:start_child(Sup, ListenerSpec) of
        {ok, _} -> {ok, Sup};
        {error, {Reason, _ChildSpec}} ->
            {error, Reason}
    end.

%% @doc Get listener.
-spec(listener(pid()) -> pid()).
listener(Sup) -> child_pid(Sup, listener).

%% @doc Get connection supervisor.
-spec(connection_sup(pid()) -> pid()).
connection_sup(Sup) -> child_pid(Sup, connection_sup).

%% @doc Get acceptor supervisor.
-spec(acceptor_sup(pid()) -> pid()).
acceptor_sup(Sup) -> child_pid(Sup, acceptor_sup).

%%--------------------------------------------------------------------
%% GET/SET APIs
%%--------------------------------------------------------------------

get_options(Sup) ->
    esockd_dtls_listener:options(listener(Sup)).

get_acceptors(Sup) ->
    esockd_dtls_acceptor_sup:count_acceptors(acceptor_sup(Sup)).

get_max_connections(Sup) ->
    esockd_connection_sup:get_max_connections(connection_sup(Sup)).

set_max_connections(Sup, MaxConns) ->
    esockd_connection_sup:set_max_connections(connection_sup(Sup), MaxConns).

get_current_connections(Sup) ->
    esockd_connection_sup:count_connections(connection_sup(Sup)).

get_shutdown_count(Sup) ->
    esockd_connection_sup:get_shutdown_count(connection_sup(Sup)).

get_access_rules(Sup) ->
    esockd_connection_sup:access_rules(connection_sup(Sup)).

allow(Sup, CIDR) ->
    esockd_connection_sup:allow(connection_sup(Sup), CIDR).

deny(Sup, CIDR) ->
    esockd_connection_sup:deny(connection_sup(Sup), CIDR).

%%--------------------------------------------------------------------
%% Supervisor callbacks
%%--------------------------------------------------------------------

init([]) ->
    {ok, {{rest_for_one, 10, 3600}, []}}.

%%--------------------------------------------------------------------
%% Uitls
%%--------------------------------------------------------------------

child_pid(Sup, ChildId) ->
    hd([Pid || {Id, Pid, _, _}
               <- supervisor:which_children(Sup), Id =:= ChildId]).

upgrade_funs(Opts) ->
    lists:append([ssl_upgrade_fun(Opts), proxy_upgrade_fun(Opts)]).

ssl_upgrade_fun(Opts) ->
    [esockd_transport:ssl_upgrade_fun(proplists:get_value(dtls_options, Opts, []))].

proxy_upgrade_fun(Opts) ->
    case proplists:get_bool(proxy_protocol, Opts) of
        false -> [];
        true  -> [esockd_transport:proxy_upgrade_fun(Opts)]
    end.

