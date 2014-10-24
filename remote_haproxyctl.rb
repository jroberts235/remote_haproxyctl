#!/usr/bin/env ruby
# version 0.1.0

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


# setup global logging
@log = Logger.new('remote_cmd.log', 'daily')
@log.datetime_format = "%Y-%m-%d %H:%M:%S"


# pull in Cmd-line options
options = Options.new
options.parse_options


# Net::SSH related variables
user               = options.config[:user] || (`whoami`).strip
ssh_key            = options.config[:ssh_key]
target_host        = options.config[:host_name] 
enable_node_name   = options.config[:enable] 
disable_node_name  = options.config[:disable]
environment        = options.config[:environment]
verbose            = options.config[:verbose]
max_conn_attempts  = 20


# Chef::API related variables
chef_user_name     = options.config[:chef_username] || user
pem_file           = options.config[:pem_file] || pemfile = ".chef/#{chef_user_name}.pem"
chef_url           = "http://#{options.config[:chef_server]}:#{options.config[:chef_server_port]}"
chef_server_object = ChefClient.new(chef_user_name, pem_file, chef_url)
node_query_object  = NodeQuery.new(chef_server_object.url)


# sanity check the Cmd-line options
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
  # query Chef for hosts from the ENV provided and have a specific ROLE associated
  hosts_in_env = get_list_of_nodes_from_chef(app_roles, environment, node_query_object)
end


# create an array of commands to send to each target_host
chain_of_commands(enable_node_name, 'enable')   if enable_node_name         # --enable
chain_of_commands(disable_node_name, 'disable') if disable_node_name        # --disable
chain_of_commands('localhost', 'health')        if options.config[:health]  # --health
@command << options.config[:command]            if options.config[:command] # or use provided command (-x)


# create a hash of hostnames to execute with an array of commands to execute on those hosts
hosts_to_execute_on_h = {}
hosts_in_env.each do |node|
    hosts_to_execute_on_h[node] = @command
end


# execute the final command
execute_remote_cmd(hosts_to_execute_on_h, user, ssh_key, max_conn_attempts, verbose)  


@output.each do |line|

    puts "#{line}" unless line.empty?

end
