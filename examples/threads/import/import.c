/*
    import.c -- Execute Lisp code from C-generated threads
*/
/*
    Copyright (c) 2005, Juan Jose Garcia Ripoll.

    ECL is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    See file '../Copyright' for full details.
*/

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <pthread.h>

/*
 * GOAL:        To execute lisp code from threads which have not
 *              been generated by our lisp environment.
 *
 * ASSUMES:     ECL has been configured with threads (--enable-threads)
 *              and installed somewhere on the path.
 *
 * COMPILE:     Run "make" from the command line.
 *
 *
 * When this example is compiled and run, it generates a number of
 * threads, each one executing some interpreted code -- in this case
 * a bunch of PRINT statements.
 *
 * Importing other threads into lisp is possible if these threads have
 * been intercepted by the garbage collector. The way to do it is to
 * include the <ecl.h> on the source code that generates the threads,
 * as we do here. This takes care of replacing calls to phtread_create
 * or CreateThread (in unix and Windows respectively) with the
 * GC_pthread_create and GC_CreateThread functions.
 */
/* Unfortunately, the Bohem-Weiser garbage collector does not keep track
 * of its configuration. We have to add the following flags by hand in
 * order to force pthread_create being redefined.
 */
#define GC_THREADS
#define _REENTRANT
#include <ecl/gc/gc.h>
#include <ecl/ecl.h>


static void *
thread_entry_point(void *data)
{
        cl_object form = (cl_object)data;

        /*
         * This is the entry point of the threads we have created.
         * These threads have no valid lisp environment. The following
         * routine initializes the lisp and makes it ready for working
         * in this thread.
         */
        ecl_import_current_thread(Cnil, Cnil);

        /*
         * Here we execute some lisp code code.
         */
        cl_eval(form);

        /*
         * Finally, when we exit the thread we have to release the
         * resources allocated by the lisp environment.
         */
        ecl_release_current_thread();
        return NULL;
}


int main(int narg, char **argv)
{
        pthread_t child_thread;
        int i, code;

        /*
         * First of all, we have to initialize the ECL environment.
         * This should be done from the main thread.
         */
        cl_boot(narg, argv);

        /*
         * Here we spawn 10 threads using the OS functions. The
         * current version is for Unix and uses pthread_create.
         * Since we have included <gc.h>, pthread_create will be
         * replaced with the appropiate routine from the garbage
         * collector.
         */
        cl_object sym_print = c_string_to_object("PRINT");

        /*
         * This array will keep the forms we want to evaluate from
         * being garbage collected.
         */
        volatile cl_object forms[4];

        for (i = 0; i < 4; i++) {
                forms[i] = cl_list(2, sym_print, MAKE_FIXNUM(i));
                code = pthread_create(&child_thread, NULL, thread_entry_point,
                                      (void*)forms[i]);
                if (code) {
                        printf("Unable to create thread\n");
                        exit(1);
                }
        }

        /*
         * Here we wait for the last thread to finish.
         */
        pthread_join(child_thread, NULL);

        return 0;
}
