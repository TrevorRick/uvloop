@cython.internal
@cython.no_gc_clear
@cython.freelist(DEFAULT_FREELIST_SIZE)
cdef class Handle:
    def __cinit__(self, Loop loop, object callback, object args):
        self.callback = callback
        self.args = args
        self.cancelled = 0
        self.done = 0
        self.loop = loop

        IF DEBUG:
            self.loop._debug_cb_handles_total += 1
            self.loop._debug_cb_handles_count += 1

    IF DEBUG:
        def __dealloc__(self):
            self.loop._debug_cb_handles_count -= 1
            if self.done == 0 and self.cancelled == 0:
                raise RuntimeError('Active Handle is deallacating')

    cdef inline _run(self):
        if self.cancelled == 1 or self.done == 1:
            return

        callback = self.callback
        args = self.args

        self.callback = None
        self.args = None

        self.done = 1
        try:
            self.loop._executing_py_code = 1
            try:
                if args is not None:
                    callback(*args)
                else:
                    callback()
            finally:
                self.loop._executing_py_code = 0
        except Exception as ex:
            self.loop.call_exception_handler({
                'message': 'Exception in callback {}'.format(callback),
                'exception': ex
            })

    cdef _cancel(self):
        self.cancelled = 1
        self.callback = None
        self.args = None

    # Public API

    def cancel(self):
        self._cancel()


@cython.internal
@cython.no_gc_clear
@cython.freelist(DEFAULT_FREELIST_SIZE)
cdef class TimerHandle:
    def __cinit__(self, Loop loop, object callback, object args,
                  uint64_t delay):

        self.loop = loop
        self.callback = callback
        self.args = args
        self.closed = 0

        self.timer = UVTimer.new(
            loop, <method_t*>&self._run, self, delay)

        self.timer.start()

        # Only add to loop._timers when `self.timer` is successfully created
        loop._timers.add(self)

        IF DEBUG:
            self.loop._debug_cb_timer_handles_total += 1
            self.loop._debug_cb_timer_handles_count += 1

    IF DEBUG:
        def __dealloc__(self):
            self.loop._debug_cb_timer_handles_count -= 1
            if self.closed == 0:
                raise RuntimeError('open TimerHandle is deallacating')

    cdef _cancel(self):
        if self.closed == 1:
            return
        self.closed = 1

        self.timer._close()
        self.timer = None  # let it die asap

        self.callback = None
        self.args = None

        self.loop._timers.remove(self)

    cdef _run(self):
        if self.closed == 1:
            return

        callback = self.callback
        args = self.args
        self._cancel()

        try:
            self.loop._executing_py_code = 1
            try:
                if args is not None:
                    callback(*args)
                else:
                    callback()
            finally:
                self.loop._executing_py_code = 0
        except Exception as ex:
            self.loop.call_exception_handler({
                'message': 'Exception in callback {}'.format(callback),
                'exception': ex
            })

    # Public API

    def cancel(self):
        self._cancel()