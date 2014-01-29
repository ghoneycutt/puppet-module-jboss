module Puppet::Parser::Functions
  newfunction(:clean_name, :type => :rvalue, :doc => <<-EOS
    Takes one argument, a hostname, and strips whitespace, periods, and
    underscores from the the string and returns it as a string.
    EOS
  ) do |args|

    raise(Puppet::ParseError, "clean_name(): Wrong number of arguments " +
      "given (#{args.size} for 1)") if args.size != 1

    args[0].gsub(/(_|\s|\.)/, '')
  end
end
