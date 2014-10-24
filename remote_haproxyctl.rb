#!/usr/bin/env ruby

require './ops_lib.rb'
require './options.rb'
require 'logger'

@output = []
@command = []

# allow ctrl-c without barffing
trap "SIGINT" do
  puts "Exiting"
  exit 130
end


# setup logging
@log = Logger.new('remote_cmd.log', 'daily')
@log.datetime_format = "%Y-%m-%d %H:%M:%S"


# Cmd-line options
options = Options.new
options.parse_options


# Net::SSH related 
user               = options.config[:user] || (`whoami`).strip
ssh_key            = options.config[:ssh_key]
target_host        = options.config[:host_name] 
enable_node_name   = options.config[:enable] 
disable_node_name  = options.config[:disable]
environment        = options.config[:environment]
verbose            = options.config[:verbose]
max_conn_attempts  = 20


# Chef::API related
chef_user_name     = options.config[:chef_username] || user
pem_file           = options.config[:pem_file] || pemfile = ".chef/#{chef_user_name}.pem"
chef_url           = "http://#{options.config[:chef_server]}:#{options.config[:chef_server_port]}"
chef_server_object = ChefClient.new(chef_user_name, pem_file, chef_url)
node_query_object  = NodeQuery.new(chef_server_object.url)


if options.config[:health]
    abort 'ERROR: You must supply a Target host (-H) when getting a health check' unless options.config[:health] and target_host
end
abort "ERROR: Either supply an Environment or a Host" unless (target_host || environment)
abort "ERROR: You cannot supply an Environment and a Host" if (target_host and environment)
abort "ERROR: You did not supply an action" unless (options.config[:health] or options.config[:enable] or options.config[:disable] or options.config[:command])
abort "ERROR: You cannot supply a -x command with any other actions" if options.config[:command] and (options.config[:health] or options.config[:enable] or options.config[:disable])


# Array of Apps/Roles to send to Chef in node query
app_roles = []
app_roles << 'ng-www-app'        if options.config[:www]
app_roles << 'ng-pub_api-app'    if options.config[:pubapi]
app_roles << 'ng-hybris-app'     if options.config[:hybris]
app_roles << 'ng-artemis'        if options.config[:artemis]
app_roles << 'ng-load_balancer'  if options.config[:lb]
 

# create an array of target_host(s) to act upon
hosts_in_env = []
if target_host 
  # use host provided on cmd line
  hosts_in_env << target_host
else
  # search Chef for hosts from the ENV provided and have a certain ROLE associated
  hosts_in_env = get_list_of_nodes_from_chef(app_roles, environment, node_query_object)
end


# create an array of commands to send to each target_host
chain_of_commands(enable_node_name, 'enable')   if enable_node_name
chain_of_commands(disable_node_name, 'disable') if disable_node_name
chain_of_commands('localhost', 'health')        if options.config[:health]
@command << options.config[:command]            if options.config[:command]


# create a hash of hostnames to execute with an array of commands to execute
hosts_to_execute_on_h = {}
hosts_in_env.each do |node|
    hosts_to_execute_on_h[node] = @command
end



# two arrays to store state in
#before = []
#after = []

#before = get_current_state(host, 'sudo haproxyctl show health', user, ssh_key, max_conn_attempts, verbose, node_names_a) unless options.config[:health]
execute_remote_cmd(hosts_to_execute_on_h, user, ssh_key, max_conn_attempts, verbose)
#after = get_current_state(host, 'sudo haproxyctl show health', user, ssh_key, max_conn_attempts, verbose, node_names_a) unless options.config[:health]


#puts "#{host} :: #{after - before}" unless options.config[:health]

@output.each do |line|

    puts "#{line}" unless line.empty?

end
