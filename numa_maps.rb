#!/usr/bin/ruby

pid = ARGV[0].to_i
# puts "read /proc/#{pid}/numa_maps"
nrs = {}
File.read("/proc/#{pid}/numa_maps").split("\n").each do |line|
  line.scan(/\bN\d+=\d+\b/).each do |item|
    item =~ /\bN(\d+)=(\d+)\b/
    nrs[$1] = 0 if nrs[$1].nil?
    nrs[$1] += $2.to_i
  end
end

p nrs
