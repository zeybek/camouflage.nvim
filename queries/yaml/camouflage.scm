; camouflage.nvim - YAML key-value pairs
; Captures block and flow style mappings

(block_mapping_pair
  key: (_) @key
  value: (flow_node
    [(plain_scalar) (double_quote_scalar) (single_quote_scalar)] @value))

(flow_pair
  key: (flow_node) @key
  value: (flow_node
    [(plain_scalar) (double_quote_scalar) (single_quote_scalar)] @value))
