%%------------------------------------------------------------------------------
%% Copyright (c) 2014, Feng Lee <feng.lee@slimchat.io>
%% 
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%% 
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.
%%------------------------------------------------------------------------------
-module(echo_server).

-export([start_link/1, 
		 init/1, 
		 loop/2]).

start_link(Socket) ->
	Pid = spawn_link(?MODULE, init, [Socket]),
	{ok, Pid}.

init(Socket) ->
	esockd_client:accepted(Socket),
	loop(Socket, state).

loop(Socket, State) ->
	case gen_tcp:recv(Socket, 0) of
		{ok, Data} -> 
			{ok, Name} = inet:sockname(Socket),
			%io:format("~p: ~s~n", [Name, Data]),
			gen_tcp:send(Socket, Data),
			loop(Socket, State);
		{error, Reason} ->
			{stop, Reason}
	end. 

