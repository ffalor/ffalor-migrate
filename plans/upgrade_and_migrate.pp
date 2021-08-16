# This plan uses the puppet_agent::install task to install/upgrade puppet agent on the target node.
# It then migrates the node to a new puppet master.
# @summary A plan to upgrade puppet agent, and then migrate them to a new puppet master.
# @param targets The targets to run on.
# @param server Specifies the new puppet master server to migrate to.
# @param ca_server Specifies the new puppet master ca_server to migrate to. Don't provide a value if you don't use a CA Server.
# @param port Specifies the puppet master port to check.
# @param section Specifies the puppet.conf section to update.
# @param verify_connection Verify the connection to the new puppet master.
# @param version The version of puppet-agent to install (defaults to latest when no agent is installed)
# @param collection The Puppet collection to install from (defaults to puppet, which maps to the latest collection released)
# @param yum_source The source location to find yum repos (defaults to yum.puppet.com)
# @param apt_source The source location to find apt repos (defaults to apt.puppet.com)
# @param mac_source The source location to find mac packages (defaults to downloads.puppet.com)
# @param windows_source The source location to find windows packages (defaults to downloads.puppet.com)
# @param install_options optional install arguments to the windows installer (defaults to REINSTALLMODE=\"amus\")
# @param stop_service Whether to stop the puppet agent service after install"
# @param retry The number of retries in case of network connectivity failures
plan migrate::upgrade_and_migrate (
  TargetSpec $targets,
  String $server,
  Optional[Integer] $port = 8140,
  Optional[String] $ca_server = undef,
  Optional[String] $section = 'agent',
  Optional[Boolean] $verify_connection = true,
  Optional[String] $version = undef,
  Optional[Enum[puppet6, puppet7, puppet, puppet6-nightly, puppet7-nightly, puppet-nightly]] $collection = 'puppet',
  Optional[String] $yum_source = 'yum.puppet.com',
  Optional[String] $apt_source = 'apt.puppet.com',
  Optional[String] $mac_source = 'downloads.puppet.com',
  Optional[String] $windows_source = 'downloads.puppet.com',
  Optional[String] $install_options = 'REINSTALLMODE=\"amus\"',
  Optional[Boolean] $stop_service = false,
  Optional[Integer] $retry = 5,

) {
  $install_puppet_output = run_task('puppet_agent::install',
    $targets,
    '_catch_errors' => true,
    'version' => $version,
    'collection' => $collection,
    'yum_source' => $yum_source,
    'apt_source' => $apt_source,
    'mac_source' => $mac_source,
    'windows_source' => $windows_source,
    'install_options' => $install_options,
    'stop_service' => $stop_service,
    'retry' => $retry,
  )

  $install_puppet_result_set = case $install_puppet_output {
    ResultSet: { $install_puppet_output }
    Error['bolt/run-failure'] : { $install_puppet_output.details['result_set'] }
    default : { fail_plan($install_puppet_output) } }

  out::message($install_puppet_result_set)
  if $install_puppet_result_set.ok_set.count == 0 {
    fail_plan('Failed to install/upgrade puppet')
  }

  $migrate_output = run_task('migrate',
    $install_puppet_result_set.ok_set.targets,
    'server' => $server,
    'port' => $port,
    'ca_server' => $ca_server,
    'section' => $section,
    'verify_connection' => $verify_connection
  )

  return $migrate_output
}
