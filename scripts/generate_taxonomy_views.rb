#!/usr/bin/env ruby
# SPDX-FileCopyrightText: Copyright © 2026 ReallyMe LLC. All rights reserved
#
# SPDX-License-Identifier: Apache-2.0

require "fileutils"
require "tempfile"
require "yaml"

ROOT = File.expand_path("..", __dir__)
MASTER_PATH = ENV.fetch("REALLYME_IDENTITY_TAXONOMY_PATH", File.join(ROOT, "master-identity-taxonomy.yaml"))
OUTPUT_DIR = ENV.fetch("REALLYME_IDENTITY_TAXONOMY_VIEWS_DIR", File.join(ROOT, "taxonomy-views"))
SOURCE_NAME = "master-identity-taxonomy.yaml"

HEADER = <<~HEADER
  # SPDX-FileCopyrightText: Copyright © 2026 ReallyMe LLC. All rights reserved
  #
  # SPDX-License-Identifier: Apache-2.0
  #
  # GENERATED FILE. Do not edit by hand.
  # Regenerate with: ruby scripts/generate_taxonomy_views.rb

HEADER

def sdk_first_resource_names(doc)
  doc.fetch("taxonomy_guidance").fetch("sdk_first_path").map { |entry| entry.split(".").first }.uniq
end

def select_resources_by_owner(resources, owner)
  resources.each_with_object({}) do |(name, resource), selected|
    next unless resource.is_a?(Hash) && resource["owner"] == owner

    selected[name] = resource
  end
end

def select_resources_by_name(resources, names)
  names.each_with_object({}) do |name, selected|
    resource = resources[name]
    selected[name] = resource if resource
  end
end

def select_operations(doc, operation_ids)
  registry = doc.fetch("operation_registry", {})
  operation_ids.each_with_object({}) do |operation_id, selected|
    entry = registry[operation_id]
    selected[operation_id] = entry if entry
  end
end

def operation_ids_for_sdk_first(doc)
  doc.fetch("taxonomy_guidance").fetch("sdk_first_path").map { |path| "identity.#{path}" }
end

def generated_document(schema, title, body)
  {
    "schema" => schema,
    "title" => title,
    "generated_from" => SOURCE_NAME
  }.merge(body)
end

def yaml_for(document)
  dumped = YAML.dump(document).gsub(/^[ \t]+'$/, "'")
  HEADER + dumped
end

def write_or_check(path, content, check:)
  if check
    unless File.exist?(path)
      warn "missing generated taxonomy view: #{path}"
      return false
    end

    current = File.read(path, encoding: "UTF-8")
    return true if current == content

    warn "stale generated taxonomy view: #{path}"
    Tempfile.create("taxonomy-view") do |expected|
      expected.write(content)
      expected.flush
      system("diff", "-u", path, expected.path)
    end
    return false
  end

  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content, encoding: "UTF-8")
  true
end

check = ARGV.include?("--check")
doc = YAML.safe_load(File.read(MASTER_PATH, encoding: "UTF-8"), aliases: true)
resources = doc.fetch("identity")
sdk_operation_ids = operation_ids_for_sdk_first(doc)

views = {
  "sdk_surface.yaml" => generated_document(
    "reallyme.identity.sdk_surface.v1",
    "ReallyMe Identity SDK Surface",
    {
      "taxonomy_guidance" => {
        "sdk_first_path" => doc.fetch("taxonomy_guidance").fetch("sdk_first_path")
      },
      "operation_identity" => doc.fetch("operation_identity"),
      "operation_registry" => select_operations(doc, sdk_operation_ids),
      "sdk_command_registry" => doc.fetch("sdk_command_registry"),
      "sdk_dto_registry" => doc.fetch("sdk_dto_registry"),
      "resources" => select_resources_by_name(resources, sdk_first_resource_names(doc))
    }
  ),
  "hosted_api.yaml" => generated_document(
    "reallyme.identity.hosted_api.v1",
    "ReallyMe Identity Hosted API Taxonomy",
    {
      "hosted_first_path" => doc.fetch("taxonomy_guidance").fetch("hosted_first_path"),
      "resources" => select_resources_by_owner(resources, "hosted_service")
    }
  ),
  "protocol_capabilities.yaml" => generated_document(
    "reallyme.identity.protocol_capabilities.v1",
    "ReallyMe Identity Protocol And Capability Taxonomy",
    {
      "credential_formats" => doc.fetch("credential_formats"),
      "standards" => doc.fetch("standards"),
      "profiles" => doc.fetch("profiles"),
      "metadata_specs" => doc.fetch("metadata_specs"),
      "transports" => doc.fetch("transports"),
      "feature_flags" => doc.fetch("feature_flags"),
      "availability" => doc.fetch("availability"),
      "execution_targets" => doc.fetch("execution_targets"),
      "fail_closed_capabilities" => doc.fetch("fail_closed_capabilities"),
      "capability_registry" => doc.fetch("capability_registry"),
      "capability_query" => resources.dig("sdk", "subresources", "capabilities"),
      "Capability" => doc.fetch("types").fetch("Capability")
    }
  ),
  "type_system.yaml" => generated_document(
    "reallyme.identity.type_system.v1",
    "ReallyMe Identity Type System",
    {
      "surface_scope" => doc.fetch("surface_scope"),
      "availability" => doc.fetch("availability"),
      "execution_targets" => doc.fetch("execution_targets"),
      "sdk_dto_registry" => doc.fetch("sdk_dto_registry"),
      "types" => doc.fetch("types")
    }
  ),
  "operation_registry.yaml" => generated_document(
    "reallyme.identity.operation_registry.v1",
    "ReallyMe Identity Operation Registry",
    {
      "operation_identity" => doc.fetch("operation_identity"),
      "operation_registry" => doc.fetch("operation_registry"),
      "sdk_command_registry" => doc.fetch("sdk_command_registry"),
      "oauth_scopes" => doc.fetch("oauth_scopes")
    }
  ),
  "conformance_matrix.yaml" => generated_document(
    "reallyme.identity.conformance_matrix.v1",
    "ReallyMe Identity Conformance Matrix",
    {
      "standards" => doc.fetch("standards"),
      "sdk_command_registry" => doc.fetch("sdk_command_registry").transform_values do |entry|
        entry.slice("operation_id", "taxonomy_ref", "boundaries", "required_capabilities")
      end,
      "check_registries" => resources.each_with_object({}) do |(name, resource), selected|
        selected[name] = resource["checks"] if resource.is_a?(Hash) && resource.key?("checks")
      end
    }
  )
}

ok = views.map do |filename, document|
  write_or_check(File.join(OUTPUT_DIR, filename), yaml_for(document), check: check)
end.all?

if ok
  puts(check ? "taxonomy views up to date" : "taxonomy views generated")
else
  exit 1
end
