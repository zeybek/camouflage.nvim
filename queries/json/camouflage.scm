; camouflage.nvim - JSON key-value pairs
; Captures key-value pairs and scalar array items for masking

(pair
  key: (string) @key
  value: (_) @value)

(pair
  key: (string) @key
  value: (array [(string) (number) (true) (false)] @value))
