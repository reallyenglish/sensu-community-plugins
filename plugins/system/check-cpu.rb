#!/usr/bin/env ruby
#
# Check CPU Plugin
#

require 'rubygems' if RUBY_VERSION < '1.9.0'
require 'sensu-plugin/check/cli'
require 'sensu-plugin/utils'

include Sensu::Plugin::Utils

class CheckCPU < Sensu::Plugin::Check::CLI

  option :warn,
    :short => '-w WARN',
    :proc => proc {|a| a.to_f },
    :default => 80

  option :crit,
    :short => '-c CRIT',
    :proc => proc {|a| a.to_f },
    :default => 100

  case os
  when "linux"
    option :sleep,
      :long => '--sleep SLEEP',
      :proc => proc {|a| a.to_f },
      :default => 1
  end

  case os
  when "linux"
    [:user, :nice, :system, :idle, :iowait, :irq, :softirq, :steal, :guest].each do |metric|
      option metric,
        :long  => "--#{metric}",
        :description => "Check cpu #{metric} instead of total cpu usage",
        :boolean => true,
        :default => false
    end
  when "freebsd"
  end

  def get_cpu_stats
    case os
    when "linux"
      File.open("/proc/stat", "r").each_line do |line|
        info = line.split(/\s+/)
        name = info.shift
        return info.map{|i| i.to_f} if name.match(/^cpu$/)
      end
    when "freebsd"
      us, sy, id = 0, 0, 0
      IO.popen("vmstat -w1 -c1") do |io|
        io.each_line do |line|
          # XXX vmstat(8) does not have an option to disable the header
          if (line =~ /^\s+proc\s+memory\s+page\s+disks\s+faults\s+cpu/ || line =~ /^r\s+b\s+w\s+avm\s+fre\s+flt\s+re\s+pi\s+po\s+fr\s+sr\s+ad0\s+cd0\s+in\s+sy\s+cs\s+us\s+sy\s+id/)
            next
          else
            us, sy, id = line.split(/\s+/)[-3..-1]
          end
        end
      end
      us.to_f + sy.to_f
    end
  end

  def run
    checked_usage = nil
    msg = nil
    case os
    when "linux"
      metrics = [:user, :nice, :system, :idle, :iowait, :irq, :softirq, :steal, :guest]

      cpu_stats_before = get_cpu_stats
      sleep config[:sleep]
      cpu_stats_after = get_cpu_stats

      cpu_total_diff = 0.to_f
      cpu_stats_diff = []
      metrics.each_index do |i|
        # Some OS's don't have a 'guest' values (RHEL)
        unless cpu_stats_after[i].nil?
          cpu_stats_diff[i] = cpu_stats_after[i] - cpu_stats_before[i]
          cpu_total_diff += cpu_stats_diff[i]
        end
      end

      cpu_stats = []
      metrics.each_index do |i|
        cpu_stats[i] = 100*(cpu_stats_diff[i]/cpu_total_diff)
      end

      cpu_usage = 100*(cpu_total_diff - cpu_stats_diff[3])/cpu_total_diff
      checked_usage = cpu_usage

      self.class.check_name 'CheckCPU TOTAL'
      metrics.each do |metric|
        if config[metric]
          self.class.check_name "CheckCPU #{metric.to_s.upcase}"
          checked_usage = cpu_stats[metrics.find_index(metric)]
        end
      end

      msg = "total=#{cpu_usage.round(2)}"
      cpu_stats.each_index {|i| msg += " #{metrics[i]}=#{cpu_stats[i].round(2)}"}
    when "freebsd"
      checked_usage = get_cpu_stats
      msg = "total=#{checked_usage}"
    end

    message msg

    critical if checked_usage > config[:crit]
    warning if checked_usage > config[:warn]
    ok
  end

end
