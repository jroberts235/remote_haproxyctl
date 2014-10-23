#!/usr/bin/env ruby

require './ops_lib.rb'
require './options.rb'
require 'logger'

@command_s # class variable to store the master command in

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


#abort "ERROR: Either supply an Environment or a Host" if (target_host || environment)
#abort "ERROR: You cannot supply an Environment and a Host" if target_host and environment


# Array of Apps/Roles to send to Chef in node query
app_roles = []
app_roles << 'ng-www-app'        if options.config[:www]
app_roles << 'ng-pub_api-app'    if options.config[:pubapi]
app_roles << 'ng-hybris-app'     if options.config[:hybris]
app_roles << 'ng-artemis'        if options.config[:artemis]
app_roles << 'ng-load_balancer'  if options.config[:lb]


# create an array of target_host(s) to act upon
if target_host 
  # use node provided on cmd line
  nodes_in_env_list = []
  nodes_in_env_list << target_host
else
  # search Chef for nodes from the ENV provided and have a certain ROLE associated
  nodes_in_env_list = get_list_of_nodes_from_chef(app_roles, environment, node_query_object)
end


unless options.config[:health]
     # unless a health check, create an array out of the nodes to disable or enable
     #node_names_string = enable_node_name ? enable_node_name : node_names_string = disable_node_name
     node_names_string = "#{enable_node_name.strip(/\n)}",
     node_names_string += #{disable_node_name.strip(/\n)}"
     node_names_a = create_array_of_node_names(node_names_string)
p node_names_string ; exit
end


# if more than one node to enable/disable, build a long string of commands to execute
if options.config[:health]
    command = "sudo haproxyctl show health"
else
    if enable_node_name # can be a comma-seperated list of nodes to enable
         command = chain_of_commands(node_names_a, 'enable')
    elsif disable_node_name # can be a comma-seperated list af nodes to disable
         command = chain_of_commands(node_names_a, 'disable')
    end 
end

puts @command_s ; exit

# execute cmd on array of nodes
nodes_in_env_list.each do |node| 

    # two arrays to store state in
    before = []
    after = []

    before = get_current_state(node, 'sudo haproxyctl show health', user, ssh_key, max_conn_attempts, verbose, node_names_a) unless options.config[:health]
    @output = execute_remote_cmd(node, @command_s, user, ssh_key, max_conn_attempts, verbose)
    after = get_current_state(node, 'sudo haproxyctl show health', user, ssh_key, max_conn_attempts, verbose, node_names_a) unless options.config[:health]


    puts "#{node} :: #{after - before}" unless options.config[:health]

    @output.each do |line|
    
        puts "#{line}" unless line.empty?

    end
end
