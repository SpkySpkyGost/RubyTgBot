This is some sort of a total mess.

Issues (23.09.25):

* Faraday ssl certificates issues (seems like part of/used in tg bot library
OpenSSL::SSL::SSLSocket#sysread_nonblock: SSL_read: unexpected eof while reading (Faraday::SSLError)

Possible "solution": 
-Wrap listen loop and API requests in retry/rescue logic

* NoMethodError – treating Integer as a chat/message
General error: NoMethodError - undefined method 'chat' for an instance of Integer

Possible "solution": 
-Refactor the code (seems like it's in main.rb, but Im kinda not sure at the moment of writing this list)
-add listen/rescue logic too
