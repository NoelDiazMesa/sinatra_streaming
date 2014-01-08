# Imports
require 'sinatra'
require 'haml'
require 'json'

class ChatWithFrames < Sinatra::Base
  
  # Server Configuration
  configure do
    set server: 'thin', connections: [], port: 3000
    enable :sessions
  end
  
  # Class variables definition and default assignment
  @@clientsByConnection ||= {}
  @@clientsByName ||= {}
  @@usernames ||= {}
  @@anonymous_counter ||= 0
  @@user_stream_clients ||= []
  @@private ||= {}
  
  # Setting up a thread that sends the user list to clients every second
  Thread.new do
    while true do
      sleep 1
      
      user_list = @@clientsByName.keys.sort
      
      @@user_stream_clients.each do |client| 
        client << "Info: {#{%Q{"users"}}:#{user_list.to_json}, #{%Q{"num"}}:#{user_list.size} }\n\n" 
      end
      
    end
  end
  
  # Route definition
  get '/' do
    if session['error']
      error = session['error']
      session['error'] = nil
      haml :index, :locals => { :error_message => error }
    else
      haml :index
    end
  end
  
  get '/chat' do
    haml :chat
  end
  
  post '/register-to-chat' do
    username = params[:username]
    if (not @@clientsByName.has_key? username)
      session['user'] = username
      redirect '/chat'
    else
      session['error'] = 'Sorry, the username is already taken.'
      redirect '/'
    end
  end
  
  get '/chat-stream', provides: 'text/event-stream' do
    content_type 'text/event-stream'
    
    if (session['user'] == nil)
      redirect '/'
    else
      username = session['user']
    end
    
    stream :keep_open do |out|
      add_connection(out, username)
      
      out.callback { remove_connection(out, username) }
      out.errback { remove_connection(out, username) }
    end
  end
  
  get '/chat-users', provides: 'text/event-stream' do
    stream :keep_open do |out|
      add_user_stream_client(out)
      
      out.callback { remove_user_stream_client out }
      out.errback { remove_user_stream_client out }
    end
  end
  
  post '/chat' do
    message = params[:message]
    if message =~ /\s*\/(\w+):/
      name = $1
      sender = session['user']
      if ((@@clientsByName.has_key? name) and (name != sender))
        if ((@@private[name] == nil) and (@@private[sender]==nil)) 
          @@private[name]=sender
          @@private[sender]=name
          stream_receiver = @@clientsByName[name]
          stream_sender = @@clientsByName[sender]
          stream_receiver << "Info: Chateando con #{sender}\n\n"
          stream_sender << "Info: Chateando con #{name}\n\n"
        else 
          stream_sender = @@clientsByName[sender]
          stream_sender << "Info: Para establecer chat con #{name} cierre chats anteriores \n\n"
        end       
      else #User not found, then broadcast
        broadcast(message, session['user'])
      end
    elsif (message == "salir")
      sender = session['user']
      stream_receiver = @@clientsByName[@@private[sender]]
      stream_sender = @@clientsByName[sender]
      stream_receiver << "Info: Se ha cerrado la conversacion con #{sender}\n\n"
      stream_sender << "Info: Se ha cerrado la conversacion \n\n"
      @@private[@@private[sender]]= nil
      @@private[sender]= nil    
    else
      name = $1 
      sender = session['user']
       if ((@@private[sender] != nil))
        stream_receiver = @@clientsByName[@@private[sender]]
        stream_sender = @@clientsByName[sender]
        stream_receiver << "Info: #{sender}: #{message}\n\n"
        stream_sender << "Info: #{sender}: #{message}\n\n"
      else
        broadcast(message, session['user'])
      end
    end
    "Message Sent" 
  end
  
  get '/*' do
    redirect '/'
  end
  
  private
  def add_connection(stream, username) 
    @@clientsByConnection[stream] = username
    @@clientsByName[username] = stream
    @@private[username] = nil
  end
  
  def add_user_stream_client(stream)
    @@user_stream_clients += [stream]
  end
  
  def remove_user_stream_client(stream)
    @@user_stream_clients.delete stream
  end
  
  def remove_connection(stream, username)
    @@clientsByConnection.delete stream
    @@clientsByName.delete username
    @@private[@@private[username]] = nil
    @@private.delete username
  end
  
  def broadcast(message, sender)
    @@clientsByConnection.each_key { |stream| stream << "Info: #{sender}: #{message}\n\n" }
  end
  
  def pop_username_from_list(id)
    username = @@usernames[id]
    @@usernames.delete id
    return username
  end
  
end

ChatWithFrames.run!