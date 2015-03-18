#!/bin/sh
# -*- tab-width:4;indent-tabs-mode:nil -*-
# ex: ts=4 sw=4 et

#-env ERL_FULLSWEEP_AFTER 10
erl -pa ebin -pa ../../ebin -pa ../../deps/*/ebin -smp true +K true +P 200000 -env ERL_MAX_PORTS 100000 -env ERTS_MAX_PORTS 100000  -s echo_server
