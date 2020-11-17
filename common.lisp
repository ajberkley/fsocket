;;;; Copyright (c) Frank James 2015 <frank.a.james@gmail.com>
;;;; This code is licensed under the MIT license.

;;; This file defines the functions and structures which are common to all platforms.

(in-package #:fsocket)

(defun htons (integer)
  "Return a 16-bit big-endian integer"
  (logior (ash (logand integer #xff00) -8)
          (ash (logand integer #x00ff) 8)))

(defun ntohs (integer)
  "Return a 16-bit integer converted from big-endian"
  (logior (ash (logand integer #x00ff) 8)
          (ash (logand integer #xff00) -8)))

(defun htonl (integer)
  "Return a 32-bit big-endian integer"
  (logior (ash (logand integer #xff000000) -24)
          (ash (logand integer #x00ff0000) -8)
          (ash (logand integer #x0000ff00) 8)
          (ash (logand integer #x000000ff) 24)))

;; #+or(win32 windows)
;; (progn
;;   ;; u_short WSAAPI htons(
;;   ;;   _In_ u_short hostshort
;;   ;; );
;;   (defcfun (htons "htons" :convention :stdcall) :uint16
;;     (hs :uint16))
  
;;   ;; u_short WSAAPI ntohs(
;;   ;;   _In_ u_short netshort
;;   ;; );
;;   (defcfun (ntohs "ntohs" :convention :stdcall) :uint16
;;     (n :uint16))

;; ;; u_long WSAAPI htonl(
;; ;;   _In_ u_long hostlong
;; ;; );
;;   (defcfun (htonl "htonl" :convention :stdcall) :uint32
;;     (x :uint32))
  
;; )

;; #-(or win32 windows)
;; (progn
  
;;   (defcfun (htons "htons") :uint16
;;     (i :uint16))
  
;;   (defcfun (ntohs "ntohs") :uint16
;;     (i :uint16))

;;   (defcfun (htonl "htonl") :uint32
;;     (i :uint32))  
;; )


(defstruct sockaddr-in
  (addr (make-array 4 :initial-element 0))
  (port 0))

;; struct sockaddr_in {
;;     short            sin_family;   // e.g. AF_INET
;;     unsigned short   sin_port;     // e.g. htons(3490)
;;     struct in_addr   sin_addr;     // see struct in_addr, below
;;     char             sin_zero[8];  // zero this if you want to
;; };
(defcstruct (sockaddr-in :class sockaddr-in-tclass)
  (family :uint16)
  (port :uint16)
  (addr :uint8 :count 4)
  (zero :uint8 :count 8))

(defmethod translate-from-foreign (ptr (type sockaddr-in-tclass))
  (let ((saddr (make-sockaddr-in)))
    (setf (sockaddr-in-port saddr)
          (ntohs (foreign-slot-value ptr '(:struct sockaddr-in) 'port))
          (sockaddr-in-addr saddr) (make-array 4))
    (dotimes (i 4)
      (setf (aref (sockaddr-in-addr saddr) i)
            (mem-aref (foreign-slot-value ptr '(:struct sockaddr-in) 'addr)
                      :uint8
                      i)))
    saddr))

(defmethod translate-into-foreign-memory ((saddr sockaddr-in) (type sockaddr-in-tclass) ptr)
  ;; freebsd has a slightly different structure layout.
  ;; the first 16 bits are split into an 8-bit length and an 8-bit family, instead of the usual 16-bit family
  #+freebsd(setf (mem-ref ptr :uint8 0) 16 ;; structure size 
                 (mem-ref ptr :uint8 1) +af-inet+)
  #-freebsd(setf (foreign-slot-value ptr '(:struct sockaddr-in) 'family) +af-inet+)
  
  (setf (foreign-slot-value ptr '(:struct sockaddr-in) 'port) (htons (sockaddr-in-port saddr)))
  (dotimes (i 4)
    (setf (mem-aref (foreign-slot-value ptr '(:struct sockaddr-in) 'addr)
                    :uint8
                    i)
          (aref (sockaddr-in-addr saddr) i)))
  ptr)

(defun dotted-quad-to-inaddr (string &optional (error-p t))
  (do ((addr (make-array 4))
       (i 0 (1+ i))
       (pos nil))
      ((= i 4) addr)
    (let ((np (position #\. string :start (or pos 0))))
      (when (and (< i 3) (not np))
	(if error-p
	    (error "Invalid dotted quad string")
	    (return-from dotted-quad-to-inaddr nil)))

      (let ((x (parse-integer string
			      :start (or pos 0) :end np
			      :junk-allowed (not error-p))))
	(when (null x) (return-from dotted-quad-to-inaddr nil))
	(setf (aref addr i) x))

      (when np (setf pos (1+ np))))))

(defun dotted-quad-p (string)
  (dotted-quad-to-inaddr string nil))

(defun inaddr-to-dotted-quad (inaddr)
  (format nil "~A.~A.~A.~A"
	  (aref inaddr 0)
	  (aref inaddr 1)
	  (aref inaddr 2)
	  (aref inaddr 3)))

(defun sockaddr-in (&optional inaddr port)
  "Allocate a SOCKADDR-IN address structure. 
INADDR ::= a vector of 4 octets specifying the internet address. May be 
entered in the \"dotted quad\" string format.
If not supplied the wildcard address is used.
PORT ::= integer specifying the port number. If not supplied port 0 will be used.

Returns a new SOCKADDR-IN structure."
  (make-sockaddr-in :addr (cond
			    ((null inaddr) #(0 0 0 0))
			    ((stringp inaddr) (dotted-quad-to-inaddr inaddr))
			    ((vectorp inaddr) inaddr)
			    ((integerp inaddr)
			     (vector (logand (ash inaddr -24) #xff)
				     (logand (ash inaddr -16) #xff)
				     (logand (ash inaddr -8) #xff)
				     (logand inaddr #xff)))
			    (t (error "Invalid inaddr value ~S" inaddr)))
		    :port (or port 0)))

;; -------------------------------

(defstruct sockaddr-in6
  (addr (make-array 8 :initial-element 0))
  (port 0)
  (flowinfo 0)
  (scopeid 0))

;; struct sockaddr_in6 {
;;     sa_family_t     sin6_family;   /* AF_INET6 */
;;     in_port_t       sin6_port;     /* port number */
;;     uint32_t        sin6_flowinfo; /* IPv6 flow information */
;;     struct in6_addr sin6_addr;     /* IPv6 address */
;;     uint32_t        sin6_scope_id; /* Scope ID (new in 2.4) */
;; };
(defcstruct (sockaddr-in6 :class sockaddr-in6-tclass)
  (family :uint16)
  (port :uint16)
  (flowinfo :uint32)
  (addr :uint16 :count 8)
  (scopeid :uint32))

(defmethod translate-from-foreign (ptr (type sockaddr-in6-tclass))
  (let ((saddr (make-sockaddr-in6)))
    (setf (sockaddr-in6-port saddr)
          (ntohs (foreign-slot-value ptr '(:struct sockaddr-in6) 'port))
          (sockaddr-in6-flowinfo saddr)
          (ntohs (foreign-slot-value ptr '(:struct sockaddr-in6) 'flowinfo))
          (sockaddr-in6-scopeid saddr)
          (ntohs (foreign-slot-value ptr '(:struct sockaddr-in6) 'scopeid))
          ;; allocate an 8 uint16 vector for the inaddr6
          (sockaddr-in6-addr saddr) (make-array 8))
    (dotimes (i 8)
      (setf (aref (sockaddr-in6-addr saddr) i)
            (ntohs (mem-aref (foreign-slot-value ptr '(:struct sockaddr-in6) 'addr)
                             :uint16
                             i))))
    saddr))

(defmethod translate-into-foreign-memory ((saddr sockaddr-in6) (type sockaddr-in6-tclass) ptr)
  ;; freebsd has a slightly different structure layout.
  ;; the first 16 bits are split into an 8-bit length and an 8-bit family, instead of the usual 16-bit family
  #+freebsd(setf (mem-ref ptr :uint8 0) 16 ;; structure size 
                 (mem-ref ptr :uint8 1) +af-inet6+)
  #-freebsd(setf (foreign-slot-value ptr '(:struct sockaddr-in6) 'family) +af-inet6+)

  (setf (foreign-slot-value ptr '(:struct sockaddr-in6) 'port) (htons (sockaddr-in6-port saddr))
        (foreign-slot-value ptr '(:struct sockaddr-in6) 'flowinfo) (sockaddr-in6-flowinfo saddr)
        (foreign-slot-value ptr '(:struct sockaddr-in6) 'scopeid) (sockaddr-in6-scopeid saddr))
  (dotimes (i 8)
    (setf (mem-aref (foreign-slot-value ptr '(:struct sockaddr-in6) 'addr)
                    :uint16
                    i)
          (htons (aref (sockaddr-in6-addr saddr) i))))
  ptr)


(defun sockaddr-in6 (&optional addr port scopeid)
  (make-sockaddr-in6 :addr (or addr #(0 0 0 0 0 0 0 0))
                     :port (or port 0)
                     :scopeid (or scopeid 0)))


(defun loopback-p (addr)
  "Returns true if the address references IPv4 127.0.0.1 or IPv6 ::1, false otherwise. 
ADDR ::= a SOCKADDR-IN or SOCKADDR-IN6 address structure."
  (etypecase addr 
    (sockaddr-in (equalp (sockaddr-in-addr addr) #(127 0 0 1)))
    (sockaddr-in6 (equalp (sockaddr-in6-addr addr) #(0 0 0 0 0 0 0 1)))))

;; (defun subnet-p (addr)
;;   "Returns true if the address is a valid subnet address."
;;   nil)

(defun sockaddr= (sa1 sa2)
  (etypecase sa1
    (sockaddr-in
     (when (typep sa2 'sockaddr-in)
       (and (equalp (sockaddr-in-addr sa1) (sockaddr-in-addr sa2))
	    (= (sockaddr-in-port sa1) (sockaddr-in-port sa2)))))
    (sockaddr-in6
     (when (typep sa2 'sockaddr-in6)
       (and (equalp (sockaddr-in6-addr sa1) (sockaddr-in6-addr sa2))
	    (= (sockaddr-in6-port sa1) (sockaddr-in6-port sa2)))))))0

;; ----------------------------

;; unix sockets are posix only 
#+(or linux freebsd darwin)
(progn

(defcstruct (sockaddr-un :class sockaddr-un-tclass)
  (family :uint16)
  (path :uint8 :count 108))

(defmethod translate-from-foreign (ptr (type sockaddr-un-tclass))
  ;; UNIX sockets are just strings naming files 
  (foreign-string-to-lisp (foreign-slot-pointer ptr '(:struct sockaddr-un) 'path)))

(defmethod translate-into-foreign-memory ((saddr string) (type sockaddr-un-tclass) ptr)
  ;; freebsd has a slightly different structure layout.
  ;; the first 16 bits are split into an 8-bit length and an 8-bit family, instead of the usual 16-bit family
  #+freebsd(setf (mem-ref ptr :uint8 0) 16 ;; structure size 
                 (mem-ref ptr :uint8 1) +af-unix+)
  #-freebsd(setf (foreign-slot-value ptr '(:struct sockaddr-un) 'family) +af-unix+)

  (lisp-string-to-foreign saddr 
                          (foreign-slot-pointer ptr '(:struct sockaddr-un) 'path)
                          108)
  ptr)

)

;; --------------------------

(defun translate-sockaddr-family (ptr)
  #+(or freebsd darwin)(mem-ref ptr :uint8 1)
  #-(or freebsd darwin)(mem-ref ptr :uint16 0))

(defun translate-sockaddr-from-foreign (ptr)
  (let ((family 
         #+(or freebsd darwin)(mem-ref ptr :uint8 1)
         #-(or freebsd darwin)(mem-ref ptr :uint16 0)))
    (cond
      ((= family +af-inet+)
       (mem-ref ptr '(:struct sockaddr-in)))
      ((= family +af-inet6+)
       (mem-ref ptr '(:struct sockaddr-in6)))
      #+(or linux freebsd darwin)
      ((= family +af-unix+)
       (mem-ref ptr '(:struct sockaddr-un)))
      (t (error 'fsocket-error :msg (format nil "Unknown address family ~A" family))))))
      
;; --------------------------

;; Q: should the events be a bitmask or a list of symbols?

(defclass pollfd ()
  ((fd :initarg :fd :initform -1 :accessor pollfd-fd)
   (events :initarg :events :initform 0 :accessor pollfd-events)
   (revents :initarg :revents :initform 0 :accessor pollfd-revents)))

(defun poll-event (int-or-sym)
  "Map an event name to an event flag or vice versa."
  (etypecase int-or-sym
    (integer
     (ecase int-or-sym
       (#x0001 :pollin)
       (#x0004 :pollout)
       (#x0008 :pollerr)
       (#x0010 :pollhup)
       (#x0020 :pollnval)))
    (symbol
     (ecase int-or-sym
       (:pollin #x0001)
       (:pollout #x0004)
       (:pollerr #x0008)
       (:pollhup #x0010)
       (:pollnval #x0020)))))

(defun poll-events (&rest events)
  "Map an event integer to a list of event names, or a list of event names to an event integer."
  (etypecase (car events)
    (integer
     (do ((ret nil)
          (flag 1 (ash flag 1))
          (e (car events) (ash e -1)))
         ((zerop e) (nreverse ret))
       (unless (zerop (logand e 1))
         (push (poll-event flag) ret))))
    (symbol
     (let ((e 0))
       (dolist (event events)
         (setf e (logior e (poll-event event))))
       e))))

(defun poll-event-p (event &optional name)
  "Event predicate.
EVENT ::= event integer.
NAME ::= event name to test. If not supplied, indicates whether any event is pending."
  (if name
      (not (zerop (logand event (poll-event name))))
      (not (zerop event))))

(defmacro doevents ((pollfd event) poll-form &body body)
  "Evaluate the POLL-FORM and iterate over each of the pollfds with events pending.
On each iteration, POLLFD will be bound to the associated pollfd strcuture and EVENTS will be bound
to a list of symbols naming each pending event."
  `(dolist (,pollfd ,poll-form)
     (when (poll-event-p (pollfd-revents ,pollfd))
       (dolist (,event (poll-events (pollfd-revents ,pollfd)))
         ,@body))))


(defstruct adapter
  name
  type
  address
  index
  unicast
;;  anycast
;;  multicast
  ;;  dns
  netmask
  broadcast
  status
  mtu)

(defmacro with-udp-socket ((var &optional port) &body body)
  "Evaludate BODY with VAR bound to a UDP socket. 
VAR ::= variable that holds the socket.
PORT ::= the port to bind VAR to, defaults to the wildcard port 0."
  `(let ((,var (open-socket)))
     (socket-bind ,var (sockaddr-in nil ,port))
     (unwind-protect (progn ,@body)
       (close-socket ,var))))

(defmacro with-tcp-socket ((var &optional port) &body body)
  "Evaluate BODY with VAR bound to a listening TCP socket.
VAR ::= variable that holds the listening TCP socket.
PORT ::= port to bind socket to, defaults to the wildcard port 0."
  `(let ((,var (open-socket :type :stream)))
     (socket-bind ,var (sockaddr-in nil ,port))
     (socket-listen ,var)
     (unwind-protect (progn ,@body)
       (close-socket ,var))))

(defmacro with-tcp-connection ((var addr) &body body)
  "Evaluate BODY with VAR bound to a connected TCP socket.
VAR ::= variable
ADDR ::= address to connect to."
  `(let ((,var (open-socket :type :stream)))
     (unwind-protect
	  (progn
	    (socket-bind ,var (sockaddr-in nil nil))
	    (socket-connect ,var ,addr)
	    ,@body)
       (close-socket ,var))))

(defmacro with-socket ((var &optional type family) &body body)
  "Execute the body ensuring the socket bound to VAR is closed."
  `(let ((,var (open-socket :family ,(or family :inet) :type ,(or type :stream))))
     (unwind-protect (progn ,@body)
       (close-socket ,var))))

  
(defmacro with-poll ((var) &body body)
  "Evaludate BODY with VAR bound to a poll context."
  `(let ((,var (open-poll)))
     (unwind-protect (progn ,@body)
       (close-poll ,var))))

(defun sockaddr-string (addr)
  "Generate a string of format a.b.c.d:port from the address."
  (etypecase addr
    (sockaddr-in
     (let ((a (sockaddr-in-addr addr)))
       (format nil "~A.~A.~A.~A:~A"
	       (aref a 0) (aref a 1) (aref a 2) (aref a 3) (sockaddr-in-port addr))))))

(defun string-sockaddr (string)
  "Parses a string in the format a.b.c.d[:port] i.e. a dotted quad with
optional port. If the port is not specified it defaults to 0."
  (let ((pos (position #\: string :test #'char=)))
    (let ((instr (if pos
		     (subseq string 0 pos)
		     string)))
      (sockaddr-in (dotted-quad-to-inaddr instr)
		   (if pos
		       (parse-integer string :start (1+ pos))
		       0)))))

(defstruct can-interface
  (name "any"))

(defstruct can-packet
  id
  data
  timestamp
  origin)

(defun parse-can-packet (packet)
  (values
   (can-packet-id packet)
   (can-packet-data packet)
   (can-packet-timestamp packet)
   (can-packet-origin packet)))

#-(or win32 windows)
(progn
  (defcfun (%read "read") :int
    (fd :int)
    (buffer :pointer)
    (count :int))
  
  (defcfun (%write "write") :int
    (fd :int)
    (buffer :pointer)
    (count :int)))
