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
%%% eSockd TCP/SSL Socket Acceptor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(esockd_acceptor).

-author('feng@emqtt.io').

-include("esockd.hrl").

-behaviour(gen_server).

-export([start_link/3]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-type socket() :: inet:socket() | esockd:ssl_socket().

-type sockfun() :: fun((inet:socket()) -> {ok, socket()} | {error, any()}).

-record(state, {conn_sup    :: pid(),
                lsock       :: inet:socket(),
                sockfun     :: sockfun(),
                ref         :: reference(), 
                emfile_count = 0}).

%%------------------------------------------------------------------------------
%% @doc 
%% Start Acceptor.
%%
%% @end
%%------------------------------------------------------------------------------
-spec start_link(ConnSup, LSock, SockFun) -> {ok, pid()} | {error, any()} when
      ConnSup   :: pid(),
      LSock     :: inet:socket(),
      SockFun   :: socket().
start_link(ConnSup, LSock, SockFun) ->
    gen_server:start_link(?MODULE, {ConnSup, LSock, SockFun}, []).

init({ConnSup, LSock, SockFun}) ->
    gen_server:cast(self(), accept),
    {ok, #state{conn_sup=ConnSup, lsock=LSock, sockfun = SockFun}}.

handle_call(_Request, _From, State) ->
    {noreply, State}.

handle_cast(accept, State) ->
    accept(State);

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({inet_async, LSock, Ref, {ok, Sock}},
            State = #state{conn_sup=ConnSup, lsock=LSock, sockfun = SockFun, ref=Ref}) ->

    %% patch up the socket so it looks like one we got from
    %% gen_tcp:accept/1
    {ok, Mod} = inet_db:lookup_socket(LSock),
    inet_db:register_socket(Sock, Mod),

	{ok, Peername} = inet:peername(Sock),
	error_logger:info_msg("Accept from ~p~n", [Peername]),

    case tune_buffer_size(Sock) of
        ok -> 
			esockd_connection_sup:start_connection(ConnSup, Mod, Sock, SockFun);
        {error, enotconn} -> 
			catch port_close(Sock);
        {error, Err} -> 
			{ok, {IPAddress, Port}} = inet:sockname(LSock),
            error_logger:error_msg(
				"failed to tune buffer size of "
				"connection accepted on ~s:~p - ~s~n",
				[esockd_net:ntoab(IPAddress), Port, Err]),
            catch port_close(Sock)
    end,

    %% accept more
    accept(State);

handle_info({inet_async, LSock, Ref, {error, closed}},
            State=#state{lsock=LSock, ref=Ref}) ->
    %% It would be wrong to attempt to restart the acceptor when we
    %% know this will fail.
    {stop, normal, State};

%%TODO: async accept errors??
%% {error, timeout} ->
%% {error, econnaborted} -> ??continue?
%% {error, esslaccept} ->
%% {error, e{n,m}file} -> suspend 100??
handle_info({inet_async, LSock, Ref, {error, Error}}, 
            State=#state{lsock=LSock, ref=Ref}) ->
	sockerr(Error, State);

handle_info(resume, State) ->
    accept(State);

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% accept...
%%--------------------------------------------------------------------
accept(State = #state{lsock=LSock}) ->
    case prim_inet:async_accept(LSock, -1) of
        {ok, Ref} -> 
			{noreply, State#state{ref=Ref}};
		{error, Error} ->
			sockerr(Error, State)
    end.

%%--------------------------------------------------------------------
%% error happened...
%%--------------------------------------------------------------------
%% emfile: The per-process limit of open file descriptors has been reached.
sockerr(emfile, State = #state{emfile_count = Count}) ->
	%%avoid too many error log.. stupid??
	case Count rem 100 of 
	0 -> error_logger:error_msg("!!!acceptor suspend 100(ms), emfile error: ~p!!!~n", [Count]);
	_ -> ignore
	end,
	suspend(100, State#state{emfile_count = Count+1});

%% enfile: The system limit on the total number of open files has been reached. usually OS's limit.
sockerr(enfile, State) ->
	error_logger:error_msg("accept error: !!!enfile!!!~n"),
	suspend(100, State);

sockerr(Error, State) ->
	error_logger:error_msg("accept error: ~p~n, stopped!!!", [Error]),
	{stop, {accept_error, Error}, State}.

%%--------------------------------------------------------------------
%% suspend for a while...
%%--------------------------------------------------------------------
suspend(Time, State) -> 
    erlang:send_after(Time, self(), resume),
	{noreply, State#state{ref=undefined}, hibernate}.

tune_buffer_size(Sock) ->
    case inet:getopts(Sock, [sndbuf, recbuf, buffer]) of
        {ok, BufSizes} -> BufSz = lists:max([Sz || {_Opt, Sz} <- BufSizes]),
                          inet:setopts(Sock, [{buffer, BufSz}]);
        Error          -> Error
	end.

