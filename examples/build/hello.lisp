;;; Copyright (c) 2006, Juan Jose Garcia Ripoll.
;;;
;;; ECL is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;;     See file '../Copyright' for full details.

(ffi::clines "extern const char *hello_string;")

(ffi::def-foreign-var ("hello_string" +hello-string+) (* :char) nil)

(print (ffi:convert-from-foreign-string +hello-string+))

