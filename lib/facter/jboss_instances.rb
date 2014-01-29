# Facter fact to list all jboss instances separated with commas. Also
# dynamically create facts based on the app name with a comma separated list of
# instances.
#
# Example:
#
# jboss_instances => api_server1,api_server2,hello_world1,hello_world2
# api_server_instances => api_server1,api_server2
# hello_world_instances => hello_world1,hello_world2
#
require 'facter'

instance_path = "/usr/local/jboss/server"
jboss_instances=Array.new
myhash = {}

if File.exists?(instance_path)
  Dir.foreach(instance_path) { |entry|
    if entry =~ /.*\d$/
      jboss_instances << entry
      app_name = "#{entry.chop}_instances"
      instance = entry[-1,1]
      if ! myhash[app_name]
        myhash[app_name] = []
      end
      myhash[app_name] << entry
    end
  }
  if jboss_instances.size > 0
    Facter.add(:jboss_instances) do
      setcode do
        jboss_instances.sort.join(',')
      end
    end
  end
  myhash.each_pair do |k,v|
    Facter.add("#{k}") do
      setcode do
        v.sort.join(',')
      end
    end
  end
end
