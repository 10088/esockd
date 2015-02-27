%%%-----------------------------------------------------------------------------
%%% @Copyright (C) 2014-2015, Feng Lee <feng@emqtt.io>
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------
%%% @doc
%%% eSockd connection supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------

%%TODO: experimental supervisor for sock connections.....

-module(esockd_connection_sup).

-author('feng@emqtt.io').

-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/3, start_connection/4, count/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {name, max_conns = 1024, cur_conns = 0, callback}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Name, Options, Callback) ->
    gen_server:start_link({local, Name}, ?MODULE, [Name, Options, Callback], []).

count(Sup, clients) ->
	gen_server:call(Sup, {count, clients}).

%%called by acceptor
start_connection(Sup, Mod, Sock, SockFun) ->
	case gen_server:call(Sup, {start_client, Sock}) of
	{ok, Client, Callback} -> 
		Mod:controlling_process(Sock, Client), 
		case exported(Callback, go) of
			{true, M} -> 
				M:go(Client, {esockd_transport, Sock, SockFun});
			false -> 
				esockd_connection:go(Client, {esockd_transport, Sock, SockFun})
		end,
		{ok, Client};
	{error, Error} ->
		{error, Error}
	end.

exported(Callback, _Fun) when is_function(Callback) ->
	false;

exported(Callback, F) when is_tuple(Callback) ->
	M = element(1, Callback),
    exported(M, F);

exported(M, F) when is_atom(M) ->
	case erlang:function_exported(M, F, 2) of
		true -> {true, M};
		false -> false
	end.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init([Name, Options, Callback]) ->
    process_flag(trap_exit, true),
	MaxConns = esockd_option:getopt(max_connections, Options, 1024),
	error_logger:info_msg("[~s] max_connections: ~p", [Name, MaxConns]),
    {ok, #state{name = Name, max_conns = MaxConns, callback = Callback}}.

handle_call({count, clients}, _From, State=#state{cur_conns=Cur}) ->
	{reply, Cur, State};

handle_call({start_client, Sock}, _From, State =
            #state{name = Name, max_conns = Max, cur_conns = Cur}) when Cur >= Max ->
	%%TODO: FIXME Later..., error message flood...
	error_logger:error_msg("[~s] cannot start connection for exceed max limit!", [Name]),
	gen_tcp:close(Sock),
    {reply, {error, too_many_clients}, State};

handle_call({start_client, Sock}, _From, State = #state{name = Name, callback=Callback}) ->
	case esockd_connection:start_link(Callback, Sock) of
	{ok, Pid} ->
		%%TODO: process dictionary or map in state??
		put(Pid, true),
		{reply, {ok, Pid, Callback}, incr(State)};
	{error, Error} ->
		error_logger:error_msg("[~s] Failed to start connection: ~p~n", [Name, Error]),
		{reply, {error, Error}, State}
	end;

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, normal}, State = #state{name = Name}) ->
	case erase(Pid) of
	true ->
		{noreply, decr(State)};
	undefined ->
		error_logger:error_msg("[~s] unexpected exit: ~p", [Name, Pid]),
		{noreply, State}
	end;

%%TODO: FIXME Later...
handle_info({'EXIT', Pid, Reason}, State) ->
	error_logger:error_msg("client:~p exited for ~p~n", [Pid, Reason]),
    {noreply, decr(State)};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
	%%kill all child...
	[begin unlink(Pid), exit(Pid, kill) end || Pid <- get_keys(true)],
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
incr(State = #state{cur_conns = I}) ->
	State#state{cur_conns = I+1}.

decr(State = #state{cur_conns = I}) ->
	State#state{cur_conns = I-1}.

