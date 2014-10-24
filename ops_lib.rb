


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
    node_names_a.map { |name| name.strip }

    # for each name string commands together 
    node_names_a.each do |node|
      if action == 'health'
          @command << "sudo haproxyctl show health; "
      else
          @command << "sudo haproxyctl #{action} all #{node}; "
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
