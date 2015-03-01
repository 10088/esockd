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
%%% eSockd TCP/SSL Acceptor Supervisor.
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(esockd_acceptor_sup).

-behaviour(supervisor).

-export([start_link/1]).

-export([init/1]).

%%
%% @doc start acceptor supervisor
%%
-spec start_link(Manager) -> {ok, pid()} when
    Manager :: pid().
start_link(Manager) ->
    supervisor:start_link(?MODULE, [Manager]).

init([Manager]) ->
    {ok, {{simple_one_for_one, 1000, 3600},
          [{acceptor, {esockd_acceptor, start_link, [Manager]},
            transient, 5000, worker, [esockd_acceptor]}]}}.

