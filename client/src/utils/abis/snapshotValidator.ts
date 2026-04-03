export const SNAPSHOT_VALIDATOR_ABI = [
  {
    "type": "impl",
    "name": "SnapshotValidatorImpl",
    "interface_name": "metagame_extensions_presets::entry_requirement::snapshot_validator::ISnapshotValidator"
  },
  {
    "type": "struct",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::Entry",
    "members": [
      {
        "name": "address",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "count",
        "type": "core::integer::u8"
      }
    ]
  },
  {
    "type": "struct",
    "name": "core::array::Span::<metagame_extensions_presets::entry_requirement::snapshot_validator::Entry>",
    "members": [
      {
        "name": "snapshot",
        "type": "@core::array::Array::<metagame_extensions_presets::entry_requirement::snapshot_validator::Entry>"
      }
    ]
  },
  {
    "type": "enum",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotStatus",
    "variants": [
      {
        "name": "Created",
        "type": "()"
      },
      {
        "name": "InProgress",
        "type": "()"
      },
      {
        "name": "Locked",
        "type": "()"
      }
    ]
  },
  {
    "type": "struct",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotMetadata",
    "members": [
      {
        "name": "owner",
        "type": "core::starknet::contract_address::ContractAddress"
      },
      {
        "name": "status",
        "type": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotStatus"
      }
    ]
  },
  {
    "type": "enum",
    "name": "core::option::Option::<metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotMetadata>",
    "variants": [
      {
        "name": "Some",
        "type": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotMetadata"
      },
      {
        "name": "None",
        "type": "()"
      }
    ]
  },
  {
    "type": "enum",
    "name": "core::bool",
    "variants": [
      {
        "name": "False",
        "type": "()"
      },
      {
        "name": "True",
        "type": "()"
      }
    ]
  },
  {
    "type": "interface",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::ISnapshotValidator",
    "items": [
      {
        "type": "function",
        "name": "create_snapshot",
        "inputs": [],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "upload_snapshot_data",
        "inputs": [
          {
            "name": "snapshot_id",
            "type": "core::integer::u64"
          },
          {
            "name": "snapshot_values",
            "type": "core::array::Span::<metagame_extensions_presets::entry_requirement::snapshot_validator::Entry>"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "lock_snapshot",
        "inputs": [
          {
            "name": "snapshot_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "get_snapshot_metadata",
        "inputs": [
          {
            "name": "snapshot_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotMetadata>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_snapshot_entry",
        "inputs": [
          {
            "name": "snapshot_id",
            "type": "core::integer::u64"
          },
          {
            "name": "player_address",
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u8"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "is_snapshot_locked",
        "inputs": [
          {
            "name": "snapshot_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "view"
      }
    ]
  },
  {
    "type": "impl",
    "name": "EntryRequirementExtensionImpl",
    "interface_name": "metagame_extensions_interfaces::entry_requirement_extension::IEntryRequirementExtension"
  },
  {
    "type": "struct",
    "name": "core::array::Span::<core::felt252>",
    "members": [
      {
        "name": "snapshot",
        "type": "@core::array::Array::<core::felt252>"
      }
    ]
  },
  {
    "type": "enum",
    "name": "core::option::Option::<core::integer::u8>",
    "variants": [
      {
        "name": "Some",
        "type": "core::integer::u8"
      },
      {
        "name": "None",
        "type": "()"
      }
    ]
  },
  {
    "type": "interface",
    "name": "metagame_extensions_interfaces::entry_requirement_extension::IEntryRequirementExtension",
    "items": [
      {
        "type": "function",
        "name": "context_owner",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::starknet::contract_address::ContractAddress"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "registration_only",
        "inputs": [],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "valid_entry",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          },
          {
            "name": "player_address",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "qualification",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "should_ban",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          },
          {
            "name": "game_token_id",
            "type": "core::felt252"
          },
          {
            "name": "current_owner",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "qualification",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "entries_left",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          },
          {
            "name": "player_address",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "qualification",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [
          {
            "type": "core::option::Option::<core::integer::u8>"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "add_config",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          },
          {
            "name": "entry_limit",
            "type": "core::integer::u8"
          },
          {
            "name": "config",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "add_entry",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          },
          {
            "name": "game_token_id",
            "type": "core::felt252"
          },
          {
            "name": "player_address",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "qualification",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "remove_entry",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          },
          {
            "name": "game_token_id",
            "type": "core::felt252"
          },
          {
            "name": "player_address",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "qualification",
            "type": "core::array::Span::<core::felt252>"
          }
        ],
        "outputs": [],
        "state_mutability": "external"
      }
    ]
  },
  {
    "type": "impl",
    "name": "SRC5Impl",
    "interface_name": "openzeppelin_interfaces::introspection::ISRC5"
  },
  {
    "type": "interface",
    "name": "openzeppelin_interfaces::introspection::ISRC5",
    "items": [
      {
        "type": "function",
        "name": "supports_interface",
        "inputs": [
          {
            "name": "interface_id",
            "type": "core::felt252"
          }
        ],
        "outputs": [
          {
            "type": "core::bool"
          }
        ],
        "state_mutability": "view"
      }
    ]
  },
  {
    "type": "constructor",
    "name": "constructor",
    "inputs": []
  },
  {
    "type": "event",
    "name": "metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::Event",
    "kind": "enum",
    "variants": []
  },
  {
    "type": "event",
    "name": "openzeppelin_introspection::src5::SRC5Component::Event",
    "kind": "enum",
    "variants": []
  },
  {
    "type": "event",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::SnapshotCreated",
    "kind": "struct",
    "members": [
      {
        "name": "snapshot_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "owner",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      }
    ]
  },
  {
    "type": "event",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::SnapshotDataUploaded",
    "kind": "struct",
    "members": [
      {
        "name": "snapshot_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "entries",
        "type": "core::array::Span::<metagame_extensions_presets::entry_requirement::snapshot_validator::Entry>",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::SnapshotLocked",
    "kind": "struct",
    "members": [
      {
        "name": "snapshot_id",
        "type": "core::integer::u64",
        "kind": "key"
      }
    ]
  },
  {
    "type": "event",
    "name": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::Event",
    "kind": "enum",
    "variants": [
      {
        "name": "EntryValidatorEvent",
        "type": "metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::Event",
        "kind": "flat"
      },
      {
        "name": "SRC5Event",
        "type": "openzeppelin_introspection::src5::SRC5Component::Event",
        "kind": "flat"
      },
      {
        "name": "SnapshotCreated",
        "type": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::SnapshotCreated",
        "kind": "nested"
      },
      {
        "name": "SnapshotDataUploaded",
        "type": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::SnapshotDataUploaded",
        "kind": "nested"
      },
      {
        "name": "SnapshotLocked",
        "type": "metagame_extensions_presets::entry_requirement::snapshot_validator::SnapshotValidator::SnapshotLocked",
        "kind": "nested"
      }
    ]
  }
] as const;
