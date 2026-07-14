#!/usr/bin/env ruby
# SPDX-FileCopyrightText: Copyright © 2026 ReallyMe LLC. All rights reserved
#
# SPDX-License-Identifier: Apache-2.0

require "minitest/autorun"
require "open3"
require "rbconfig"
require "tempfile"
require "yaml"

ROOT = File.expand_path("..", __dir__)
MASTER_PATH = File.join(ROOT, "master-identity-taxonomy.yaml")
LINT_PATH = File.join(ROOT, "scripts", "lint_taxonomy.rb")

class TaxonomyLintTest < Minitest::Test
  def test_current_taxonomy_passes_lint
    result = run_lint(MASTER_PATH)

    assert_equal true, result.success?, result.stderr
    assert_includes result.stdout, "taxonomy lint ok"
  end

  def test_sdk_required_capabilities_must_be_declared
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("credentials.validate").fetch("required_capabilities") << "undeclared_capability"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.credentials.validate.required_capabilities has undeclared capability: undeclared_capability"
  end

  def test_sdk_optional_capabilities_must_be_declared
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("presentations.present").fetch("optional_capabilities") << "undeclared_optional_capability"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.presentations.present.optional_capabilities has undeclared capability: undeclared_optional_capability"
  end

  def test_sdk_behavior_values_must_use_declared_vocabulary
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("wallets.credentials.store").fetch("behavior")["network_access"] = "surprise_network"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, 'sdk_command_registry.wallets.credentials.store.behavior.network_access is invalid: "surprise_network"'
  end

  def test_sdk_commands_must_declare_dto_backing
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("dids.create").delete("dto_backing")
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.dids.create.dto_backing is invalid: nil"
  end

  def test_sdk_commands_must_not_track_implementation_status
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("dids.create")["implementation_status"] = "implemented"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.dids.create.implementation_status is not supported SDK command metadata"
  end

  def test_sdk_commands_must_not_track_implementation_gaps
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("dids.create")["gaps"] = ["tracked elsewhere"]
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.dids.create.gaps is not supported SDK command metadata"
  end

  def test_fail_closed_capability_rule_must_be_declared
    result = run_mutated_taxonomy do |doc|
      doc.fetch("fail_closed_capabilities")["rule"] = "Missing providers are caller-defined."
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "fail_closed_capabilities.rule must declare unsupported_capability fail-closed behavior"
  end

  def test_default_provider_must_not_leak_static_taxonomy_metadata
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("trust.evaluate").fetch("rust")["default_provider"] = "WorkflowTrustProvider"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.trust.evaluate.rust.default_provider is not supported static taxonomy metadata"
  end

  def test_sdk_first_path_targets_must_have_command_registry_entries
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").delete("wallets.open")
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_first_path target is missing sdk_command_registry entry: wallets.open"
  end

  def test_sdk_dto_backing_must_use_declared_vocabulary
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("dids.create")["dto_backing"] = "trust_me"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, 'sdk_command_registry.dids.create.dto_backing is invalid: "trust_me"'
  end

  def test_sdk_language_facade_cannot_claim_native_boundaries
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("dids.create")["dto_backing"] = "language_facade"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.dids.create.dto_backing language_facade cannot cover native boundaries: ffi, wasm, jni"
  end

  def test_wallet_core_rpc_commands_must_declare_proto_messages
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("wallets.credentials.store").delete("proto_messages")
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.wallets.credentials.store.proto_messages must be a mapping when dto_backing is wallet_core_rpc"
  end

  def test_proto_request_and_response_messages_must_match_proto_package
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("wallets.credentials.store").fetch("proto_messages")["request"] =
        "reallyme.identity.sdk.v1.PutCredentialRecordRequest"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.wallets.credentials.store.proto_messages.request must be in proto_package reallyme.wallet.v1"
  end

  def test_sdk_external_type_references_must_be_registered
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("credentials.validate").fetch("rust")["request_type"] = "CredentialValidateTypoRequest"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.credentials.validate.rust.request_type references CredentialValidateTypoRequest, which is not in types or sdk_dto_registry"
  end

  def test_sdk_result_dtos_must_declare_their_canonical_type
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("credentials.validate").delete("canonical_type")
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.credentials.validate.canonical_type must be ValidationResult for output_type CredentialValidationResult"
  end

  def test_sdk_canonical_type_must_resolve_to_shared_type
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("dids.create")["canonical_type"] = "DidDocumentDto"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.dids.create.canonical_type references DidDocumentDto, which is not in types"
  end

  def test_sdk_taxonomy_ref_must_match_operation_registry
    result = run_mutated_taxonomy do |doc|
      doc.fetch("sdk_command_registry").fetch("issuance.issue")["taxonomy_ref"] = "identity.credentials.commands.validate"
    end

    assert_equal false, result.success?
    assert_includes result.stderr, "sdk_command_registry.issuance.issue taxonomy_ref must match operation_registry.identity.issuance.issue.taxonomy_ref"
  end

  private

  LintResult = Struct.new(:success?, :stdout, :stderr, keyword_init: true)

  def run_mutated_taxonomy
    doc = YAML.safe_load(File.read(MASTER_PATH, encoding: "UTF-8"), aliases: true)
    yield doc

    Tempfile.create(["identity-taxonomy", ".yaml"]) do |file|
      file.write(YAML.dump(doc))
      file.flush

      return run_lint(file.path)
    end
  end

  def run_lint(path)
    stdout, stderr, status = Open3.capture3(
      { "REALLYME_IDENTITY_TAXONOMY_PATH" => path },
      RbConfig.ruby,
      LINT_PATH
    )
    LintResult.new(success?: status.success?, stdout: stdout, stderr: stderr)
  end
end
