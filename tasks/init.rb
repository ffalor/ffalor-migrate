#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

#Test if server can reach port and return true or false

require 'json'
require 'puppet'
require 'socket'
require 'open3'
require 'fileutils'

result = {}

# Copied fully from https://github.com/puppetlabs/puppetlabs-puppet_conf/blob/main/tasks/init.rb
# Modified a little, and new functions added
def puppet_cmd
  if Gem.win_platform?
    require 'win32/registry'
    installed_dir =
      begin
        Win32::Registry::HKEY_LOCAL_MACHINE.open('SOFTWARE\Puppet Labs\Puppet') do |reg|
          # rubocop:disable Style/RescueModifier
          # Rescue missing key
          dir = reg['RememberedInstallDir64'] rescue ''
          # Both keys may exist, make sure the dir exists
          break dir if File.exist?(dir)

          # Rescue missing key
          reg['RememberedInstallDir'] rescue ''
          # rubocop:enable Style/RescueModifier
        end
      rescue Win32::Registry::Error
        # Rescue missing registry path
        ''
      end

    puppet =
      if installed_dir.empty?
        ''
      else
        File.join(installed_dir, 'bin', 'puppet.bat')
      end
  else
    puppet = '/opt/puppetlabs/bin/puppet'
  end

  # Fall back to PATH lookup if puppet-agent isn't installed
  puppet = 'puppet' unless File.exist?(puppet)

  puppet
end

def set(setting, section, value)
	cmd = [puppet_cmd, 'config', 'set']
	cmd += ['--section', section] if section
	cmd += [setting, value]
	_stdout, stderr, status = Open3.capture3(*cmd)
	raise Puppet::Error, stderr if status != 0
	{ status: value, setting: setting, section: section }
end

def get(setting, section)
	cmd = [puppet_cmd, 'config', 'print']
	cmd += ['--section', section]
	cmd += [setting]
	stdout, stderr, status = Open3.capture3(*cmd)
	raise Puppet::Error, stderr if status != 0
	stdout.strip
end

def delete(setting, section, _value)
	cmd = [puppet_cmd, 'config', 'delete']
	cmd += ['--section', section]
	cmd += [setting]
	stdout, stderr, status = Open3.capture3(*cmd)
	raise Puppet::Error, stderr if status != 0
	{ status: stdout.strip, setting: setting, section: section }
end

def config(setting)
	cmd = [puppet_cmd, 'config', 'print']
	cmd += [setting]
	stdout, stderr, status = Open3.capture3(*cmd)
	raise Puppet::Error, stderr if status != 0
	stdout.strip
end

def run()
	cmd = [puppet_cmd, 'agent', '-t']
	return Open3.capture3(*cmd)
end

def test_connection(host, port)
    Timeout::timeout(5) do
        s = TCPSocket.new(host, port)
        s.close
        return true
    end
end

def copy_dir(path, new_path)
    # Copy path recursively to new_path
    FileUtils.cp_r(path, new_path)
end

def move_dir(path, new_path)
    # move path to new_path and overwrite existing files
    FileUtils.mv(path, new_path)
end

def purge_dir(path)
    # Delete all files in directory
    FileUtils.rm_rf(path)
end

begin
    params = JSON.load(STDIN.read)

    server = params['server']
    ca_server = params['ca_server']
    port = params['port']
    section = params['section']
    verify_connection = params['verify_connection']

    rollback_started = false
    rollback_complete = false

    ssl_dir = config('ssldir')

    if verify_connection
        server_test = test_connection(server, port)
        if ca_server
            ca_server_test = test_connection(ca_server, port)
        end
    end

    # Get current setting for server for backup
    original_server_setting = get('server', section)
    # Get current setting for ca_server for backup
    original_ca_server_setting = get('ca_server', section)

    # Update server setting
    set('server', section, server)
    # Update ca_server setting
    if ca_server
        set('ca_server', section, ca_server)
    end

    if File.directory?(ssl_dir)
        backup_ssl_dir = "#{ssl_dir}_backup"

        # Backup ssl directory
        copy_dir(ssl_dir, backup_ssl_dir)

        # Remove old ssl directory
        purge_dir(ssl_dir)
    else
        backup_ssl_dir = nil
    end

    #run_stdout, run_stderr, run_status = run()
    run_status = 0
    if run_status != 0
        # Restore original settings
        rollback_started = true

        set('server', section, original_server_setting)
        if ca_server
            set('ca_server', section, original_ca_server_setting)
        end

        if backup_ssl_dir
            purge_dir(ssl_dir)
            move_dir(backup_ssl_dir, ssl_dir)
        end

        rollback_complete = true
        raise("Unable to run puppet with new settings. Rollback complete. Error: #{run_stderr}")
    end

    result['result'] = {
        "original_settings": {
            "server": original_server_setting,
            "ca_server": ca_server ? original_ca_server_setting : nil
        },
        "new_settings": {
            "server": get('server', section),
            "ca_server": ca_server ? get('ca_server', section) : nil
        },
        "backup_ssl_dir_path": backup_ssl_dir
    }

rescue Timeout::Error
    result[:_error] = { msg: "Timeout connecting to server: #{server} or ca_server: #{ca_server} over port: #{port}.",
        kind: "Timeout::Error",
        details: { 
            class: "Timeout::Error"
        }
    }
    
rescue => e
    result[:_error] = { msg: e.message,
        kind: "Uncaught",
        details: { 
            class: e.class.to_s,
            rollback_started: rollback_started,
            rollback_complete: rollback_complete
        }
    }
end

puts result.to_json
