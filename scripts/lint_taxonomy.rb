#!/usr/bin/env ruby
# SPDX-FileCopyrightText: Copyright © 2026 ReallyMe LLC. All rights reserved
#
# SPDX-License-Identifier: Apache-2.0

require "psych"
require "yaml"

ROOT = File.expand_path("..", __dir__)
TAXONOMY_PATH = ENV.fetch("REALLYME_IDENTITY_TAXONOMY_PATH", File.join(ROOT, "master-identity-taxonomy.yaml"))

REQUEST_FIELD_FAMILIES = %w[
  all
  create_request
  create_update
  issue_request
  register_update
  revoke_suspend
].freeze

FEATURE_FLAG_VALUES = [true, false, "optional"].freeze
SUPPORT_VALUES = %w[required optional compatibility].freeze
AUTHENTICATION_VALUES = %w[none optional required].freeze
AUTHORIZATION_VALUES = %w[none required].freeze
PII_VALUES = %w[reads writes none].freeze
LATENCY_VALUES = %w[local network].freeze
NETWORK_VALUES = %w[none optional required].freeze
SDK_IDEMPOTENT_VALUES = [true, false, "provider_dependent"].freeze
SDK_SIDE_EFFECT_VALUES = %w[none provider_dependent wallet_storage].freeze
SDK_NETWORK_ACCESS_VALUES = %w[none provider_dependent forbidden].freeze
SDK_OFFLINE_CAPABLE_VALUES = [true, false, "provider_dependent"].freeze
SDK_DTO_BACKING_VALUES = %w[
  language_facade
  native_abi
  proto_message
  wallet_core_rpc
].freeze
SDK_NATIVE_BOUNDARY_SURFACES = %w[ffi wasm jni].freeze
SDK_PROTO_MESSAGE_FIELDS = %w[request response error].freeze
SDK_DTO_OWNER_REPOS = %w[
  identity-sdk
  identity
  wallet
  openidvc
  openid4vp
].freeze
SDK_DTO_REGISTRY_KEYS = %w[
  dto_backing
  owner_repo
  surfaces
].freeze
SDK_REQUIRED_CANONICAL_RESULT_TYPES = {
  "CredentialValidationResult" => "ValidationResult",
  "CredentialStatusResult" => "CredentialStatus",
  "VerificationResult" => "PresentationVerificationResult",
  "TrustEvaluationResult" => "TrustDecision",
  "StatusResolutionCheckResult" => "CredentialStatus"
}.freeze
OPERATION_TYPES = %w[
  administration
  diagnostics
  discovery
  issuance
  lifecycle
  retrieval
  transport
  verification
].freeze

OPERATION_REGISTRY_KEYS = %w[
  behavior
  breaking_changes
  documentation
  emits
  interop
  module
  names
  oauth_scopes
  operation_type
  owner
  security
  stability
  taxonomy_ref
  visibility
].freeze

COMMAND_METADATA_KEYS = %w[
  actor
  availability
  deprecated
  execution
  network_access
  operation_id
  optional
  owner
  requires
  stability
  surfaces
].freeze

SDK_TYPE_REFERENCE_KEYS = %w[
  error_type
  input_type
  output_type
  request_type
  response_type
].freeze

SDK_COMMAND_REGISTRY_KEYS = %w[
  behavior
  boundaries
  canonical_type
  docs_surface
  dto_backing
  error_domain
  error_type
  ffi
  input_type
  jni
  kotlin
  operation_id
  optional_capabilities
  output_type
  owner
  proto_messages
  proto_package
  required_capabilities
  rust
  since
  stability
  swift
  taxonomy_ref
  typescript
  wasm
].freeze

def command_names(commands)
  case commands
  when Array
    commands.flat_map { |entry| entry.is_a?(Hash) ? entry.keys : entry }.map(&:to_s)
  when Hash
    commands.keys.map(&:to_s)
  else
    []
  end
end

def command_entries(commands)
  case commands
  when Array
    commands.flat_map do |entry|
      entry.is_a?(Hash) ? entry.map { |name, metadata| [name.to_s, metadata] } : [[entry.to_s, nil]]
    end
  when Hash
    commands.map { |name, metadata| [name.to_s, metadata] }
  else
    []
  end
end

def each_mapping(node, path = [], &block)
  return unless node.is_a?(Hash)

  yield node, path
  node.each do |key, value|
    if value.is_a?(Hash)
      each_mapping(value, path + [key], &block)
    elsif value.is_a?(Array)
      value.each_with_index do |item, index|
        each_mapping(item, path + [key, index.to_s], &block) if item.is_a?(Hash)
      end
    end
  end
end

def sdk_type_references(node, path = [])
  refs = []
  case node
  when Hash
    node.each do |key, value|
      current_path = path + [key.to_s]
      refs << [current_path.join("."), value] if SDK_TYPE_REFERENCE_KEYS.include?(key.to_s) && value.is_a?(String)
      refs.concat(sdk_type_references(value, current_path)) if value.is_a?(Hash) || value.is_a?(Array)
    end
  when Array
    node.each_with_index do |value, index|
      refs.concat(sdk_type_references(value, path + [index.to_s])) if value.is_a?(Hash) || value.is_a?(Array)
    end
  end
  refs
end

def resolve_node(resources, parts)
  resource = parts.shift
  node = resources[resource]
  return nil unless node

  parts.each do |part|
    node = node.dig("subresources", part)
    return nil unless node
  end

  node
end

def command_exists?(resources, target)
  parts = target.split(".")
  command = parts.pop
  node = resolve_node(resources, parts)
  return false unless node

  command_names(node["commands"]).include?(command)
end

def resource_exists?(resources, target)
  parts = target.split(".")
  !resolve_node(resources, parts).nil?
end

def target_exists?(resources, target)
  command_exists?(resources, target) || resource_exists?(resources, target)
end

def command_ref_exists?(resources, ref)
  parts = ref.split(".")
  return false unless parts.shift == "identity"

  commands_index = parts.index("commands")
  return false unless commands_index

  command = parts[commands_index + 1]
  return false unless command

  resource_parts = parts[0...commands_index].reject { |part| part == "subresources" }
  node = resolve_node(resources, resource_parts)
  return false unless node

  command_names(node["commands"]).include?(command)
end

def collect_duplicate_keys(path)
  root = Psych.parse_file(path)
  duplicates = []

  walker = lambda do |node, path_parts|
    case node
    when Psych::Nodes::Mapping
      seen = {}
      node.children.each_slice(2) do |key_node, value_node|
        key = key_node.value
        current_path = (path_parts + [key]).join(".")
        duplicates << current_path if seen.key?(key)
        seen[key] = true
        walker.call(value_node, path_parts + [key])
      end
    when Psych::Nodes::Sequence
      node.children.each_with_index do |child, index|
        walker.call(child, path_parts + [index.to_s])
      end
    end
  end

  root.children.each { |child| walker.call(child, []) }
  duplicates
end

doc = YAML.safe_load(File.read(TAXONOMY_PATH, encoding: "UTF-8"), aliases: true)
resources = doc.fetch("identity")
errors = []

collect_duplicate_keys(TAXONOMY_PATH).each do |path|
  errors << "duplicate YAML key at #{path}"
end

sdk_command_registry = doc.fetch("sdk_command_registry", {})

doc.fetch("taxonomy_guidance").fetch("sdk_first_path").each do |target|
  errors << "sdk_first_path target does not resolve: #{target}" unless command_exists?(resources, target)
  errors << "sdk_first_path target is missing sdk_command_registry entry: #{target}" unless sdk_command_registry.key?(target)
end

Array(doc.dig("taxonomy_guidance", "hosted_first_path")).each do |resource|
  errors << "hosted_first_path resource does not resolve: #{resource}" unless resources.key?(resource)
end

surface_scope = doc.fetch("surface_scope").keys
surfaces = doc.fetch("availability").fetch("surfaces")
standards = doc.fetch("standards").keys
types = doc.fetch("types").keys
sdk_dto_registry = doc.fetch("sdk_dto_registry", {})
sdk_dto_ids = sdk_dto_registry.keys
operation_ids = doc.fetch("operation_registry", {}).keys
stability_values = doc.dig("modeling_rules", "stability").keys
capability_registry = doc.fetch("capability_registry", {})
capability_ids = capability_registry.keys
event_types = Array(resources["common_event_types"])
oauth_scopes = doc.fetch("oauth_scopes", [])
profiles = doc.fetch("profiles", [])
example_ids = doc.fetch("examples", {}).keys
guide_ids = doc.fetch("guides", {}).keys
canonical_owners = Hash.new { |hash, key| hash[key] = [] }
generated_operation_ids = Hash.new { |hash, key| hash[key] = [] }

unless doc["schema"] == "reallyme.identity.master_taxonomy.v1"
  errors << "schema must be reallyme.identity.master_taxonomy.v1"
end

taxonomy_version = doc["taxonomy"]
unless taxonomy_version.is_a?(Hash) && %w[major minor patch].all? { |field| taxonomy_version[field].is_a?(Integer) }
  errors << "taxonomy.major, taxonomy.minor, and taxonomy.patch must be integers"
end

fail_closed_rule = doc.dig("fail_closed_capabilities", "rule")
unless fail_closed_rule.is_a?(String) && fail_closed_rule.include?("unsupported_capability")
  errors << "fail_closed_capabilities.rule must declare unsupported_capability fail-closed behavior"
end

unless Array(doc.dig("types", "IdentityError", "category", "enum")).include?("unsupported_capability")
  errors << "types.IdentityError.category.enum must include unsupported_capability"
end

doc.fetch("feature_flags", {}).each do |name, config|
  value = config.is_a?(Hash) ? config["enabled"] : nil
  errors << "feature_flags.#{name}.enabled has invalid value: #{value.inspect}" unless FEATURE_FLAG_VALUES.include?(value)
end

capability_registry.each do |capability_id, capability|
  unless doc.dig("types", "Capability", "category", "enum").include?(capability["category"])
    errors << "capability_registry.#{capability_id}.category is invalid: #{capability['category']}"
  end

  unless doc.dig("types", "Capability", "status", "enum").include?(capability["status"])
    errors << "capability_registry.#{capability_id}.status is invalid: #{capability['status']}"
  end

  Array(capability["requires"]).each do |required|
    errors << "capability_registry.#{capability_id}.requires has undeclared capability: #{required}" unless capability_ids.include?(required)
  end

  Array(capability["conflicts_with"]).each do |conflict|
    errors << "capability_registry.#{capability_id}.conflicts_with has undeclared capability: #{conflict}" unless capability_ids.include?(conflict)
  end
end

doc.fetch("standards", {}).each do |name, standard|
  support = standard["support"]
  errors << "standards.#{name}.support has invalid value: #{support}" unless SUPPORT_VALUES.include?(support)
end

doc.fetch("credential_formats", {}).each do |group, formats|
  next unless formats.is_a?(Hash)

  formats.each do |name, format|
    support = format["support"]
    errors << "credential_formats.#{group}.#{name}.support has invalid value: #{support}" unless SUPPORT_VALUES.include?(support)
  end
end

sdk_dto_registry.each do |type_name, entry|
  unless entry.is_a?(Hash)
    errors << "sdk_dto_registry.#{type_name} must be a mapping"
    next
  end

  entry.keys.each do |key|
    errors << "sdk_dto_registry.#{type_name}.#{key} is not supported SDK DTO metadata" unless SDK_DTO_REGISTRY_KEYS.include?(key.to_s)
  end

  owner_repo = entry["owner_repo"]
  errors << "sdk_dto_registry.#{type_name}.owner_repo is invalid: #{owner_repo.inspect}" unless SDK_DTO_OWNER_REPOS.include?(owner_repo)

  dto_backing = entry["dto_backing"]
  errors << "sdk_dto_registry.#{type_name}.dto_backing is invalid: #{dto_backing.inspect}" unless SDK_DTO_BACKING_VALUES.include?(dto_backing)

  surfaces_value = entry["surfaces"]
  if surfaces_value.is_a?(Array) && !surfaces_value.empty?
    surfaces_value.each do |surface|
      errors << "sdk_dto_registry.#{type_name}.surfaces has undeclared surface: #{surface}" unless surfaces.include?(surface)
    end
  else
    errors << "sdk_dto_registry.#{type_name}.surfaces must be a non-empty array"
  end
end

each_mapping(resources, ["identity"]) do |node, path|
  owner = node["owner"]
  owner = nil unless owner.is_a?(String)
  errors << "#{path.join('.')} owner is undeclared: #{owner}" if owner && !surface_scope.include?(owner)

  Array(node["mechanism_for"]).each do |target|
    errors << "#{path.join('.')} mechanism_for target does not resolve: #{target}" unless target_exists?(resources, target)
  end

  Array(node["canonical_for"]).each do |canonical|
    canonical_owners[canonical] << path.join(".")
  end

  if node["checks"].is_a?(Hash)
    commands = command_names(node["commands"])
    node["checks"].keys.each do |check_key|
      errors << "#{path.join('.')} checks.#{check_key} has no command" unless commands.include?(check_key.to_s)
    end
  end

  command_entries(node["commands"]).each do |command, metadata|
    operation_path = (path + [command]).reject { |part| part == "subresources" }.join(".")
    generated_operation_ids[operation_path] << path.join(".")

    next unless metadata.is_a?(Hash)

    metadata.keys.each do |key|
      errors << "#{path.join('.')} commands.#{command}.#{key} is not supported command metadata" unless COMMAND_METADATA_KEYS.include?(key.to_s)
    end

    stability = metadata["stability"]
    errors << "#{path.join('.')} commands.#{command}.stability is invalid: #{stability}" if stability && !stability_values.include?(stability)

    Array(metadata["requires"]).each do |capability|
      errors << "#{path.join('.')} commands.#{command}.requires has undeclared capability: #{capability}" unless capability_ids.include?(capability)
    end

    Array(metadata["optional"]).each do |capability|
      errors << "#{path.join('.')} commands.#{command}.optional has undeclared capability: #{capability}" unless capability_ids.include?(capability)
    end

    if metadata.key?("deprecated") && !metadata["deprecated"].is_a?(Hash)
      errors << "#{path.join('.')} commands.#{command}.deprecated must be a mapping"
    elsif metadata["deprecated"].is_a?(Hash)
      replacement = metadata.dig("deprecated", "replacement")
      if replacement && !command_exists?(resources, replacement) && !operation_ids.include?(replacement)
        errors << "#{path.join('.')} commands.#{command}.deprecated.replacement does not resolve: #{replacement}"
      end
    end
  end

  if node["command_overrides"].is_a?(Hash)
    commands = command_names(node["commands"])
    node["command_overrides"].keys.each do |command|
      errors << "#{path.join('.')} command_overrides.#{command} has no command" unless commands.include?(command.to_s)
    end
  end

  if node["request_fields"].is_a?(Hash)
    commands = command_names(node["commands"])
    node["request_fields"].keys.each do |field_group|
      next if commands.include?(field_group.to_s) || REQUEST_FIELD_FAMILIES.include?(field_group.to_s)

      errors << "#{path.join('.')} request_fields.#{field_group} has no command or documented family"
    end
  end

  if node["views"].is_a?(Hash)
    node["views"].each do |view_name, view|
      target = view["canonical_command"]
      next unless target

      errors << "#{path.join('.')} views.#{view_name} target does not resolve: #{target}" unless command_exists?(resources, target)
    end
  end

  if node["completion_view"].is_a?(Hash)
    node["completion_view"].each do |view_name, view|
      target = view["canonical_command"]
      next unless target

      errors << "#{path.join('.')} completion_view.#{view_name} target does not resolve: #{target}" unless command_exists?(resources, target)
    end
  end

  node.fetch("boundaries", []).each do |surface|
    errors << "#{path.join('.')} boundary surface is undeclared: #{surface}" unless surfaces.include?(surface)
  end

  node.fetch("surfaces", []).each do |surface|
    errors << "#{path.join('.')} surface is undeclared: #{surface}" unless surfaces.include?(surface)
  end

  if node["availability"].is_a?(Hash)
    %w[include exclude].each do |field|
      Array(node.dig("availability", field)).each do |surface|
        errors << "#{path.join('.')} availability.#{field} surface is undeclared: #{surface}" unless surfaces.include?(surface)
      end
    end
  end
end

canonical_owners.each do |canonical, owners|
  next if owners.length == 1

  errors << "canonical_for value #{canonical} has #{owners.length} owners: #{owners.join(', ')}"
end

generated_operation_ids.each do |operation_id, owners|
  next if owners.length == 1

  errors << "generated operation_id #{operation_id} has #{owners.length} owners: #{owners.join(', ')}"
end

each_mapping(doc, []) do |node, path|
  if node.key?("default_provider")
    errors << "#{(path + ['default_provider']).join('.')} is not supported static taxonomy metadata"
  end

  owner = node["owner"]
  owner = nil unless owner.is_a?(String)
  errors << "#{path.join('.')} owner is undeclared: #{owner}" if owner && !surface_scope.include?(owner)

  unless path.first == "standards"
    if node["standards"].is_a?(Array)
      node["standards"].each do |standard|
        errors << "#{path.join('.')} standards reference is undeclared: #{standard}" unless standards.include?(standard)
      end
    end

    Array(node["specifications"]).each do |standard|
      errors << "#{path.join('.')} standards reference is undeclared: #{standard}" unless standards.include?(standard)
    end

    %w[specification data_model reference_framework].each do |field|
      standard = node[field]
      errors << "#{path.join('.')} #{field} reference is undeclared: #{standard}" if standard && !standards.include?(standard)
    end
  end

  ref = node["$ref"]
  errors << "#{path.join('.')} type reference is undeclared: #{ref}" if ref && !types.include?(ref)
end

doc.fetch("operation_registry", {}).each do |operation_id, entry|
  entry.keys.each do |key|
    errors << "operation_registry.#{operation_id}.#{key} is not supported operation metadata" unless OPERATION_REGISTRY_KEYS.include?(key.to_s)
  end

  ref = entry["taxonomy_ref"]
  errors << "operation_registry.#{operation_id} missing taxonomy_ref" unless ref
  errors << "operation_registry.#{operation_id} taxonomy_ref does not resolve: #{ref}" if ref && !command_ref_exists?(resources, ref)

  owner = entry["owner"]
  errors << "operation_registry.#{operation_id}.owner is undeclared: #{owner}" if owner && !surface_scope.include?(owner)

  stability = entry["stability"]
  errors << "operation_registry.#{operation_id}.stability is invalid: #{stability}" if stability && !stability_values.include?(stability)

  security = entry["security"]
  if security
    unless AUTHENTICATION_VALUES.include?(security["authentication"])
      errors << "operation_registry.#{operation_id}.security.authentication is invalid: #{security['authentication']}"
    end
    unless AUTHORIZATION_VALUES.include?(security["authorization"])
      errors << "operation_registry.#{operation_id}.security.authorization is invalid: #{security['authorization']}"
    end
    unless [true, false].include?(security["audit"])
      errors << "operation_registry.#{operation_id}.security.audit must be boolean"
    end
    errors << "operation_registry.#{operation_id}.security.pii is invalid: #{security['pii']}" unless PII_VALUES.include?(security["pii"])
  end

  behavior = entry["behavior"]
  if behavior
    %w[idempotent safe repeatable cacheable expensive].each do |field|
      errors << "operation_registry.#{operation_id}.behavior.#{field} must be boolean" unless [true, false].include?(behavior[field])
    end
    unless LATENCY_VALUES.include?(behavior["expected_latency"])
      errors << "operation_registry.#{operation_id}.behavior.expected_latency is invalid: #{behavior['expected_latency']}"
    end
    errors << "operation_registry.#{operation_id}.behavior.network is invalid: #{behavior['network']}" unless NETWORK_VALUES.include?(behavior["network"])
  end

  Array(entry["emits"]).each do |event|
    errors << "operation_registry.#{operation_id}.emits has undeclared event: #{event}" unless event_types.include?(event)
  end

  Array(entry["oauth_scopes"]).each do |scope|
    errors << "operation_registry.#{operation_id}.oauth_scopes has undeclared scope: #{scope}" unless oauth_scopes.include?(scope)
  end

  names = entry["names"]
  if names
    errors << "operation_registry.#{operation_id}.names.canonical must equal #{operation_id}" unless names["canonical"] == operation_id
    %w[sdk rest cli graphql].each do |field|
      errors << "operation_registry.#{operation_id}.names.#{field} must be present" unless names[field].is_a?(String)
    end
  end

  visibility = entry["visibility"]
  if visibility
    %w[public internal].each do |field|
      errors << "operation_registry.#{operation_id}.visibility.#{field} must be boolean" unless [true, false].include?(visibility[field])
    end
  end

  mod = entry["module"]
  if mod
    %w[component crate package].each do |field|
      errors << "operation_registry.#{operation_id}.module.#{field} must be present" unless mod[field].is_a?(String)
    end
  end

  operation_type = entry["operation_type"]
  errors << "operation_registry.#{operation_id}.operation_type is invalid: #{operation_type}" if operation_type && !OPERATION_TYPES.include?(operation_type)

  interop = entry["interop"]
  if interop
    Array(interop["standards"]).each do |standard|
      errors << "operation_registry.#{operation_id}.interop.standards has undeclared standard: #{standard}" unless standards.include?(standard)
    end
    Array(interop["profiles"]).each do |profile|
      errors << "operation_registry.#{operation_id}.interop.profiles has undeclared profile: #{profile}" unless profiles.include?(profile)
    end
  end

  documentation = entry["documentation"]
  if documentation
    errors << "operation_registry.#{operation_id}.documentation.hidden must be boolean" unless [true, false].include?(documentation["hidden"])
    errors << "operation_registry.#{operation_id}.documentation.examples must be an array" if documentation.key?("examples") && !documentation["examples"].is_a?(Array)
    errors << "operation_registry.#{operation_id}.documentation.guides must be an array" if documentation.key?("guides") && !documentation["guides"].is_a?(Array)
    Array(documentation["examples"]).each do |example|
      errors << "operation_registry.#{operation_id}.documentation.examples has undeclared example: #{example}" unless example_ids.include?(example)
    end
    Array(documentation["guides"]).each do |guide|
      errors << "operation_registry.#{operation_id}.documentation.guides has undeclared guide: #{guide}" unless guide_ids.include?(guide)
    end
  end

  breaking_changes = entry["breaking_changes"]
  errors << "operation_registry.#{operation_id}.breaking_changes must be an array" if breaking_changes && !breaking_changes.is_a?(Array)
end

sdk_command_registry.each do |command, entry|
  unless entry.is_a?(Hash)
    errors << "sdk_command_registry.#{command} must be a mapping"
    next
  end

  entry.keys.each do |key|
    errors << "sdk_command_registry.#{command}.#{key} is not supported SDK command metadata" unless SDK_COMMAND_REGISTRY_KEYS.include?(key.to_s)
  end

  operation_id = entry["operation_id"]
  errors << "sdk_command_registry.#{command} missing operation_id" unless operation_id

  registry_entry = operation_id ? doc.fetch("operation_registry", {})[operation_id] : nil
  errors << "sdk_command_registry.#{command} operation_id is not registered: #{operation_id}" if operation_id && !registry_entry

  taxonomy_ref = entry["taxonomy_ref"]
  errors << "sdk_command_registry.#{command} missing taxonomy_ref" unless taxonomy_ref
  errors << "sdk_command_registry.#{command} taxonomy_ref does not resolve: #{taxonomy_ref}" if taxonomy_ref && !command_ref_exists?(resources, taxonomy_ref)
  if registry_entry && taxonomy_ref && registry_entry["taxonomy_ref"] != taxonomy_ref
    errors << "sdk_command_registry.#{command} taxonomy_ref must match operation_registry.#{operation_id}.taxonomy_ref"
  end

  owner = entry["owner"]
  errors << "sdk_command_registry.#{command}.owner is undeclared: #{owner}" if owner && !surface_scope.include?(owner)

  stability = entry["stability"]
  errors << "sdk_command_registry.#{command}.stability is invalid: #{stability}" if stability && !stability_values.include?(stability)

  canonical_type = entry["canonical_type"]
  required_canonical_type = SDK_REQUIRED_CANONICAL_RESULT_TYPES[entry["output_type"]]
  if required_canonical_type && canonical_type != required_canonical_type
    errors << "sdk_command_registry.#{command}.canonical_type must be #{required_canonical_type} for output_type #{entry['output_type']}"
  elsif canonical_type && !types.include?(canonical_type)
    errors << "sdk_command_registry.#{command}.canonical_type references #{canonical_type}, which is not in types"
  end

  dto_backing = entry["dto_backing"]
  unless SDK_DTO_BACKING_VALUES.include?(dto_backing)
    errors << "sdk_command_registry.#{command}.dto_backing is invalid: #{dto_backing.inspect}"
  end

  Array(entry["required_capabilities"]).each do |capability|
    errors << "sdk_command_registry.#{command}.required_capabilities has undeclared capability: #{capability}" unless capability_ids.include?(capability)
  end

  Array(entry["optional_capabilities"]).each do |capability|
    errors << "sdk_command_registry.#{command}.optional_capabilities has undeclared capability: #{capability}" unless capability_ids.include?(capability)
  end

  entry.fetch("boundaries", []).each do |surface|
    errors << "sdk_command_registry.#{command}.boundaries has undeclared surface: #{surface}" unless surfaces.include?(surface)
  end

  native_boundaries = Array(entry["boundaries"]) & SDK_NATIVE_BOUNDARY_SURFACES
  if dto_backing == "language_facade" && !native_boundaries.empty?
    errors << "sdk_command_registry.#{command}.dto_backing language_facade cannot cover native boundaries: #{native_boundaries.join(', ')}"
  end
  if dto_backing == "native_abi" && native_boundaries.empty?
    errors << "sdk_command_registry.#{command}.dto_backing native_abi requires at least one native boundary"
  end

  proto_messages = entry["proto_messages"]
  if %w[proto_message wallet_core_rpc].include?(dto_backing)
    unless entry["proto_package"].is_a?(String) && !entry["proto_package"].empty?
      errors << "sdk_command_registry.#{command}.proto_package is required when dto_backing is #{dto_backing}"
    end

    if proto_messages.is_a?(Hash)
      unsupported_fields = proto_messages.keys.map(&:to_s) - SDK_PROTO_MESSAGE_FIELDS
      unsupported_fields.each do |field|
        errors << "sdk_command_registry.#{command}.proto_messages.#{field} is not supported"
      end

      SDK_PROTO_MESSAGE_FIELDS.each do |field|
        value = proto_messages[field]
        unless value.is_a?(String) && !value.empty?
          errors << "sdk_command_registry.#{command}.proto_messages.#{field} must be a non-empty string"
        end
      end

      if entry["proto_package"].is_a?(String) && !entry["proto_package"].empty?
        %w[request response].each do |field|
          value = proto_messages[field]
          next unless value.is_a?(String) && !value.empty?

          unless value.start_with?("#{entry['proto_package']}.")
            errors << "sdk_command_registry.#{command}.proto_messages.#{field} must be in proto_package #{entry['proto_package']}"
          end
        end
      end
    else
      errors << "sdk_command_registry.#{command}.proto_messages must be a mapping when dto_backing is #{dto_backing}"
    end
  elsif proto_messages
    errors << "sdk_command_registry.#{command}.proto_messages is only allowed for proto_message or wallet_core_rpc dto_backing"
  end

  if dto_backing == "wallet_core_rpc"
    wallet_core_methods = %w[rust ffi wasm jni].map do |lane|
      lane_metadata = entry[lane]
      lane_metadata["wallet_core_method"] if lane_metadata.is_a?(Hash)
    end.compact
    errors << "sdk_command_registry.#{command}.wallet_core_rpc requires at least one wallet_core_method lane" if wallet_core_methods.empty?
  end

  behavior = entry["behavior"]
  if behavior
    unless SDK_IDEMPOTENT_VALUES.include?(behavior["idempotent"])
      errors << "sdk_command_registry.#{command}.behavior.idempotent is invalid: #{behavior['idempotent'].inspect}"
    end
    unless SDK_SIDE_EFFECT_VALUES.include?(behavior["side_effects"])
      errors << "sdk_command_registry.#{command}.behavior.side_effects is invalid: #{behavior['side_effects'].inspect}"
    end
    unless SDK_NETWORK_ACCESS_VALUES.include?(behavior["network_access"])
      errors << "sdk_command_registry.#{command}.behavior.network_access is invalid: #{behavior['network_access'].inspect}"
    end
    unless SDK_OFFLINE_CAPABLE_VALUES.include?(behavior["offline_capable"])
      errors << "sdk_command_registry.#{command}.behavior.offline_capable is invalid: #{behavior['offline_capable'].inspect}"
    end
    unless AUTHENTICATION_VALUES.include?(behavior["authentication"])
      errors << "sdk_command_registry.#{command}.behavior.authentication is invalid: #{behavior['authentication'].inspect}"
    end
  end

  sdk_type_references(entry).each do |path, type_name|
    next if types.include?(type_name)
    next if sdk_dto_ids.include?(type_name)

    errors << "sdk_command_registry.#{command}.#{path} references #{type_name}, which is not in types or sdk_dto_registry"
  end
end

if errors.empty?
  puts "taxonomy lint ok"
else
  errors.each { |error| warn error }
  exit 1
end
