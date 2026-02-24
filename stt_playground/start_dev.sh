#!/bin/bash

STT_TRACE=1 SPEECH_BACKEND=google mix phx.server 2>&1 | tee start_dev.log
