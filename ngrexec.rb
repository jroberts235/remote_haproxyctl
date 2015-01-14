#!/usr/bin/env ruby
# version 0.1.0

class Options
    require 'mixlib/cli'
    include Mixlib::CLI

    option :host_name,
        :short => "-H TARGET_HOST",
        :long => "--host TARGET_HOST",
        :description => "The name of the target host to run the command on.",
        :required => false

    option :environment,
        :short => "-e ENVIRONMENT",
        :long => "--environment ENVIRONMENT",
        :description => "prod, stg, dev, ops, qa1, qa2, qa3, int1, int2, int3",
        :required => false

    option :user,
        :short => "-u USER",
        :long => "--USERNAME",
        :description => "Username to connect to remote host with",
        :required => false

    option :chef_username,
        :short => "-U CHEF_USERNAME",
        :long => "--chef_user_name CHEF_USERNAME",
        :description => "Client name to connect to Chef Server with",
        :required => false

    option :pem_file,
        :short => "-p PEMFILE",
        :long => "--pemfile PEMFILE",
        :description => ".pem file to connect to the Chef Server with",
        :required => false

    option :ssh_key,
        :short => "-i IDENTITY",
        :long => "--identity IDENTITY",
        :description => "SSH key to use when connecting to remote host",
        :required => false

    option :chef_server,
        :short => "-s CHEF_SERVER",
        :long => "--server CHEF_SERVER",
        :description => "Chef Server to use",
        :default => 'chefserver.ops.nastygal.com',
        :required => false

    option :chef_server_port,
        :short => "-P CHEF_SERVER_PORT",
        :long => "--port CHEF_SERVER_PORT",
        :description => "TCP port to use when connecting to the Chef Server",
        :default => 4000,
        :required => false

    option :command,
        :short => "-x COMMAND",
        :long => "--execute COMMAND",
        :description => "Command to run on remote host",
        :required => false

    option :enable,
        :long => "--enable NODE",
        :description => "Enable a node",
        :required => false

    option :health,
        :long => "--health",
        :description => "Show haproxy health check on node",
        :boolean => true,
        :required => false

    option :disable,
        :long => "--disable NODE",
        :description => "Disable a node",
        :required => false

    option :verbose,
        :short => "-v",
        :long => "--verbose",
        :description => "Verbose reporting",
        :boolean => false,
        :required => false

    option :www,
        :description => "Affect HAproxy on WWW machines in given ENV",
        :long => "--www",
        :boolean => true,
        :default => false,
        :required => false

    option :pubapi,
        :description => "Affect HAproxy on PubApi machines in given ENV",
        :long => "--pubapi",
        :boolean => true,
        :default => false,
        :required => false

    option :hybris,
        :description => "Affect HAproxy on Hybris machines in given ENV",
        :long => "--hybris",
        :boolean => true,
        :default => false,
        :required => false

    option :artemis,
        :description => "Affect HAproxy on Artemis machines in given ENV",
        :long => "--artemis",
        :boolean => true,
        :default => false,
        :required => false

    option :lb,
        :description => "Affect HAproxy on LB machines in given ENV",
        :long => "--lb",
        :boolean => true,
        :default => false,
        :required => false

    option :help,
        :long => "--help",
        :short => "-h",
        :description => "Show this message",
        :on => :tail,
        :show_options => true,
        :boolean => true,
        :exit => 0

end



class Nettools
    require 'net/ssh'

    def initialize(target_host, node_ip, max_conn_attempts, user, keys, verbose)
        conn_state = false
        counter = 0
        puts "Attempting connection to #{target_host} ... \n" if verbose
        until conn_state 
            begin
                @session = Net::SSH.start(node_ip,
                                          user,
                                          :keys => keys,
                                          :timeout => 15,
                                          :user_known_hosts_file => "/dev/null"
                                         )

            conn_state = true
            rescue Timeout::Error, Errno::ECONNREFUSED => e
                puts e.message if verbose
                puts e.backtrace.inspect if verbose 
                puts "Waiting for successful ssh connection..." if verbose
                counter += 1
                abort("Max Connection attempts reached !!") if counter == max_conn_attempts
                sleep 10
            end
        end
        puts "Successfully connected to #{node_ip}" if verbose
    end



    def run_cmd(cmd, target_host, verbose)
        puts "Executing #{cmd} on node #{target_host}" if verbose
        abort('Session is closed !!!') if @session.closed?
        @session.exec!(cmd)
    end
end




class ChefClient
    require 'chef'

    begin
        attr_accessor :name, :key, :url
        def initialize(name, key, url)
            @name = name
            @key  = key
            @url  = url

            Chef::Config[:node_name]=name
            Chef::Config[:client_key]=key
            Chef::Config[:chef_server_url]=url
        end
    rescue => e
        puts "Chef API error!"
        exit(1)
    end
end



class NodeQuery
    require 'chef/search/query'
    require 'chef/rest'
    require 'chef/node'
    require 'json'

    def initialize(url)
        begin
            @var = Chef::Search::Query.new(url) 
        rescue Chef::Exceptions::PrivateKeyMissing => e
            puts "Can't locate your Chef private key!"
            exit(1)
        end
    end

    def search(query)
        begin
            nodes = []
            results = @var.search('node', query)
            justNodes = results[0..(results.count - 3)] # drop the last 2 indexes
            justNodes[0].each do |host|
                nodes << host.to_s[/\[(.*?)\]/].tr('[]', '')  # take the name, leave the cannoli
            end
            return nodes
        rescue NoMethodError => e
            puts "Chef query error: #{query}"
            exit(1)
        end
    end
end



class NodeAttrs
    attr_accessor :results
    def initialize(node)
        begin
            var = Chef::Node.load(node)
            @results = var.display_hash
        rescue => e
            puts "Can't get attrs for node #{node}"
        end
    end
end



def get_list_of_nodes_from_chef(app_roles, environment, node_query_object)
    begin
        target_node_list = []
        app_roles.each do |role|
            target_node_list << node_query_object.search("role:#{role} AND chef_environment:#{environment}")
        end
        return target_node_list.flatten
    rescue SocketError => e
        puts "Cannot connect to Chef Server!" 
        exit(1)
    end
end



def chain_of_commands(node_names_s, action)
    node_names_a = []
    node_names_a = node_names_s.include?(',') ? node_names_s.split(',') : node_names_a << node_names_s
    node_names_a.map! { |name| name.strip } # strip any leftover ws
    node_names_a.map! { |name| name.split('.').first } # if the hostname.env is used only keep hostname

    # for each name, string commands together 
    node_names_a.each do |node|
      if action == 'health'
          @command << "sudo haproxyctl show health; "
      else
          # this is hacky but it works !
          if node.include?('www')
              @command << "sudo haproxyctl #{action} all #{node}; "
              @command << "sudo haproxyctl #{action} all #{node}:80; "
              @command << "sudo haproxyctl #{action} all #{node}:443; "
              @command << "sudo haproxyctl #{action} all #{node}:6081; "
          elsif node.include?('pub-api')
              @command << "sudo haproxyctl #{action} all #{node}; "
          end
      end
    end
end




def execute_remote_cmd(hosts_to_execute_on_h, user, ssh_key, max_conn_attempts, verbose)

    hosts_to_execute_on_h.each do |host,command|
        # get chef_name and ipaddress os host(s) to execute cmd on
        host_attrs  = NodeAttrs.new(host)
        target_host = host_attrs.results['name']
        host_ip     = host_attrs.results['automatic']['ipaddress']

    
        # establish an SSH connection to the target_host
        net_ssh = Nettools.new(target_host, host_ip, max_conn_attempts, user, ssh_key, verbose)


        # execute the command for each host provided and print returned lines if any
        command.each do |cmd|
            string = net_ssh.run_cmd("#{cmd}", target_host, verbose)
            if string
                output = string.split(/\n/) 
                output.map! { |l| "#{host}::#{l}" } 
                output.each { |line| @output << line } # add recent output to global output
            else
                puts "No output returned from #{host}"
            end

            @log.info("ON #{host} RAN '#{cmd.to_s}' AS #{user}")
        end
    end
end

begin
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
    

    
    # execute the final command on target host
    execute_remote_cmd(hosts_to_execute_on_h, user, ssh_key, max_conn_attempts, verbose)  
    

    
    @output.each do |line|
    
        puts "#{line}" unless line.empty?
    
    end
rescue => e
    puts "ERROR: #{e}"
end
