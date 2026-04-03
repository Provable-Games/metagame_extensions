export const MERKLE_VALIDATOR_ABI = [
  {
    "type": "impl",
    "name": "MerkleValidatorImpl",
    "interface_name": "metagame_extensions_presets::entry_requirement::merkle_validator::IMerkleValidator"
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
    "name": "metagame_extensions_presets::entry_requirement::merkle_validator::IMerkleValidator",
    "items": [
      {
        "type": "function",
        "name": "create_tree",
        "inputs": [
          {
            "name": "root",
            "type": "core::felt252"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "external"
      },
      {
        "type": "function",
        "name": "get_tree_root",
        "inputs": [
          {
            "name": "tree_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::felt252"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "get_tree_owner",
        "inputs": [
          {
            "name": "tree_id",
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
        "name": "get_context_tree",
        "inputs": [
          {
            "name": "context_id",
            "type": "core::integer::u64"
          }
        ],
        "outputs": [
          {
            "type": "core::integer::u64"
          }
        ],
        "state_mutability": "view"
      },
      {
        "type": "function",
        "name": "verify_proof",
        "inputs": [
          {
            "name": "tree_id",
            "type": "core::integer::u64"
          },
          {
            "name": "player_address",
            "type": "core::starknet::contract_address::ContractAddress"
          },
          {
            "name": "count",
            "type": "core::integer::u8"
          },
          {
            "name": "proof",
            "type": "core::array::Span::<core::felt252>"
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
    "name": "metagame_extensions_presets::entry_requirement::merkle_validator::MerkleValidator::TreeCreated",
    "kind": "struct",
    "members": [
      {
        "name": "tree_id",
        "type": "core::integer::u64",
        "kind": "key"
      },
      {
        "name": "owner",
        "type": "core::starknet::contract_address::ContractAddress",
        "kind": "key"
      },
      {
        "name": "root",
        "type": "core::felt252",
        "kind": "data"
      }
    ]
  },
  {
    "type": "event",
    "name": "metagame_extensions_presets::entry_requirement::merkle_validator::MerkleValidator::Event",
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
        "name": "TreeCreated",
        "type": "metagame_extensions_presets::entry_requirement::merkle_validator::MerkleValidator::TreeCreated",
        "kind": "nested"
      }
    ]
  }
] as const;
