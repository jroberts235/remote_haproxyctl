class Options
    require 'mixlib/cli'
    include Mixlib::CLI

    option :node_name,
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

    option :chef_user_name,
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

#    option :command,
#        :short => "-x COMMAND",
#        :long => "--execute COMMAND",
#        :description => "Command to run on remote host",
#        :required => false

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
        :description => "Show this message",
        :on => :tail,
        :show_options => true,
        :boolean => true,
        :exit => 0

end
