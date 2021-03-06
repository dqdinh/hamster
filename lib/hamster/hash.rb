require "hamster/immutable"
require "hamster/undefined"
require "hamster/enumerable"
require "hamster/trie"
require "hamster/set"
require "hamster/vector"
require "hamster/nested"

module Hamster
  def self.hash(pairs = nil, &block)
    (pairs.nil? && block.nil?) ? EmptyHash : Hash.new(pairs, &block)
  end

  # A `Hamster::Hash` maps from a set of unique keys to corresponding values,
  # much like a dictionary maps from words to definitions. Given a key, it can
  # efficiently store and retrieve values. Looking up a key given its value is also
  # possible, but less efficient. If an existing key is stored again, the new value
  # will replace that which was previously stored.
  #
  # It behaves much like Ruby's built-in Hash, which we will call RubyHash
  # for clarity. Like RubyHash, `Hamster::Hash` uses `#hash` and `#eql?` to define
  # equality between keys. Keys with the same `#hash` code, but which are not `#eql?`
  # to each other, can coexist in the same `Hamster::Hash`. To retrieve a previously
  # stored value, the key provided must have the same `#hash` code and be `#eql?`
  # to the one used for storage.
  #
  # A `Hamster::Hash` can be created in several ways:
  #
  #     Hamster.hash('Jane Doe' => 10, 'Jim Doe' => 6)
  #     Hamster::Hash.new(font_size: 10, font_family: 'Arial')
  #     Hamster::Hash[first_name: 'John', last_name: 'Smith']
  #
  # If you want to write your own class which inherits from `Hamster::Hash`, you can
  # use either of the latter 2 forms of initialization.
  #
  # Note that any `Enumerable` object which yields 2-element `[key, value]` arrays
  # can be used to initialize a `Hamster::Hash`. So this is also possible:
  #
  #     Hamster::Hash.new([[:first_name, 'John'], [:last_name, 'Smith']])
  #
  # Like RubyHash, key/value pairs can be added using {#store}. Unlike RubyHash,
  # a new hash is returned, and the existing one is left unchanged:
  #
  #     hash = Hamster::Hash[a: 100, b: 200]
  #     hash.store(:c, 500) # => Hamster::Hash[:a => 100, :b => 200, :c => 500]
  #     hash # => Hamster::Hash[:a => 100, :b => 200]
  #
  # You also use {#put}. The difference is that {#put} can optionally take a block which
  # is used to calculate the value to be stored:
  #
  #     hash.put(:a) { hash[:b] + 100 } # => Hamster::Hash[:a => 300, :b => 200]
  #
  # Since it is immutable, all methods which you might expect to "modify" a `Hamster::Hash`
  # actually return a new hash and leave the existing one unchanged. This means that the
  # `hash[key] = value` syntax used with RubyHashes *cannot* be used with `Hamster::Hash`.
  #
  # While a `Hamster::Hash` can iterate over its keys (or values), it does not
  # guarantee any specific iteration order (unlike RubyHash). Likewise, methods like
  # {#flatten} do not guarantee which order the returned key/value pairs will appear
  # in.
  #
  # Like RubyHash, a `Hamster::Hash` can have a default block which is used when
  # looking up a key which does not exist in the hash. Unlike RubyHash, the default
  # block will only be passed the missing key, not the hash itself:
  #
  #     hash = Hamster::Hash.new { |n| n * 10 }
  #     hash[5] # => 50
  #
  # A default block can only be set when creating a `Hamster::Hash` with `Hamster::Hash.new` or
  # {Hamster.hash Hamster.hash}, not with {Hamster::Hash.[] Hamster::Hash[]}. Default blocks
  # do not survive marshalling and unmarshalling.
  #
  class Hash
    include Immutable
    include Enumerable

    class << self
      # Create a new `Hash` populated with the given key/value pairs.
      #
      # @example
      #   Hamster::Hash["A" => 1, "B" => 2]
      #   # => Hamster::Hash["A" => 1, "B" => 2]
      #   Hamster::Hash[["A", 1], ["B", 2]]
      #   # => Hamster::Hash["A" => 1, "B" => 2]
      #
      # @return [Hash]
      def [](pairs = nil)
        (pairs.nil? || pairs.empty?) ? empty : new(pairs)
      end

      # Return an empty `Hash`. If used on a subclass, returns an empty instance
      # of that class.
      #
      # @return [Hash]
      def empty
        @empty ||= self.new
      end

      # "Raw" allocation of a new `Hash`. Used internally to create a new
      # instance quickly after obtaining a modified {Trie}.
      #
      # @return [Hash]
      # @private
      def alloc(trie = EmptyTrie, block = nil)
        obj = allocate
        obj.instance_variable_set(:@trie, trie)
        obj.instance_variable_set(:@default, block)
        obj
      end
    end

    def initialize(pairs = nil, &block)
      @trie = pairs ? Trie[pairs] : EmptyTrie
      @default = block
    end

    # Return the default block if there is one. Otherwise, return `nil`.
    #
    # @return [Proc]
    def default_proc
      @default
    end

    # Return the number of key/value pairs in this `Hash`.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].size  # => 3
    #
    # @return [Integer]
    def size
      @trie.size
    end
    alias :length :size

    # Return `true` if this `Hash` contains no key/value pairs.
    #
    # @return [Boolean]
    def empty?
      @trie.empty?
    end

    # Return `true` if the given key object is present in this `Hash`. More precisely,
    # return `true` if a key with the same `#hash` code, and which is also `#eql?`
    # to the given key object is present.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].key?("B")  # => true
    #
    # @param key [Object] The key to check for
    # @return [Boolean]
    def key?(key)
      @trie.key?(key)
    end
    alias :has_key? :key?
    alias :include? :key?
    alias :member?  :key?

    # Return `true` if this `Hash` has one or more keys which map to the provided value.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].value?(2)  # => true
    #
    # @param value [Object] The value to check for
    # @return [Boolean]
    def value?(value)
      each { |k,v| return true if value == v }
      false
    end
    alias :has_value? :value?

    # Retrieve the value corresponding to the provided key object. If not found, and
    # this `Hash` has a default block, the default block is called to provide the
    # value.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h["B"]             # => 2
    #   h.get("B")         # => 2
    #   h.get("Elephant")  # => nil
    #
    #   # Hamster Hash with a default proc:
    #   h = Hamster::Hash.new("A" => 1, "B" => 2, "C" => 3) { |key| key.size }
    #   h.get("B")         # => 2
    #   h.get("Elephant")  # => 8
    #
    # @param key [Object] The key to look up
    # @return [Object]
    def get(key)
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif @default
        @default.call(key)
      end
    end
    alias :[] :get

    # Retrieve the value corresponding to the given key object, or use the provided
    # default value or block, or otherwise raise a `KeyError`.
    #
    # @overload fetch(key)
    #   Retrieve the value corresponding to the given key, or raise a `KeyError`
    #   if it is not found.
    #   @param key [Object] The key to look up
    # @overload fetch(key) { |key| ... }
    #   Retrieve the value corresponding to the given key, or call the optional
    #   code block (with the missing key) and get its return value.
    #   @yield [key] The key which was not found
    #   @yieldreturn [Object] Object to return since the key was not found
    #   @param key [Object] The key to look up
    # @overload fetch(key, default)
    #   Retrieve the value corresponding to the given key, or else return
    #   the provided `default` value.
    #   @param key [Object] The key to look up
    #   @param default [Object] Object to return if the key is not found
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.fetch("B")         # => 2
    #   h.fetch("Elephant")  # => KeyError: key not found: "Elephant"
    #
    #   # with a default value:
    #   h.fetch("B", 99)         # => 2
    #   h.fetch("Elephant", 99)  # => 99
    #
    #   # with a block:
    #   h.fetch("B") { |key| key.size }         # => 2
    #   h.fetch("Elephant") { |key| key.size }  # => 8
    #
    # @return [Object]
    def fetch(key, default = Undefined)
      entry = @trie.get(key)
      if entry
        entry[1]
      elsif block_given?
        yield(key)
      elsif default != Undefined
        default
      else
        raise KeyError, "key not found: #{key.inspect}"
      end
    end

    # Return a new `Hash` with the existing key/value associations, plus an association
    # between the provided key and value. If an equivalent key is already present, its
    # associated value will be replaced with the provided one.
    #
    # If the `value` argument is missing, but an optional code block is provided,
    # it will be passed the existing value (or `nil` if there is none) and what it
    # returns will replace the existing value. This is useful for "transforming"
    # the value associated with a certain key.
    #
    # Avoid mutating objects which are used as keys. `String`s are an exception --
    # unfrozen `String`s which are used as keys are internally duplicated and
    # frozen.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2]
    #   h.put("C", 3)
    #   # => Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.put("B") { |value| value * 10 }
    #   # => Hamster::Hash["A" => 1, "B" => 20]
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @yield [value] The previously stored value
    # @yieldreturn [Object] The new value to store
    # @return [Hash]
    def put(key, value = yield(get(key)))
      new_trie = @trie.put(key, value)
      if new_trie.equal?(@trie)
        self
      else
        self.class.alloc(new_trie, @default)
      end
    end

    # Return a new `Hash` with a deeply nested value modified to the result of
    # the given code block.  When traversing the nested `Hash`es and `Vector`s,
    # non-existing keys are created with empty `Hash` values.
    #
    # The code block receives the existing value of the deeply nested key (or
    # `nil` if it doesn't exist). This is useful for "transforming" the value
    # associated with a certain key.
    #
    # Note that the original `Hash` and sub-`Hash`es and sub-`Vector`s are left
    # unmodified; new data structure copies are created along the path wherever
    # needed.
    #
    # @example
    #   hash = Hamster::Hash["a" => Hamster::Hash["b" => Hamster::Hash["c" => 42]]]
    #   hash.update_in("a", "b", "c") { |value| value + 5 }
    #   # => Hamster::Hash["a" => Hamster::Hash["b" => Hamster::Hash["c" => 47]]]
    #
    # @param key_path [Object(s)] List of keys which form the path to the key to be modified
    # @yield [value] The previously stored value
    # @yieldreturn [Object] The new value to store
    # @return [Hash]
    def update_in(*key_path, &block)
      if key_path.empty?
        raise ArgumentError, "must have at least one key in path"
      end
      key = key_path[0]
      if key_path.size == 1
        new_value = block.call(get(key))
      else
        value = fetch(key, EmptyHash)
        new_value = value.update_in(*key_path[1..-1], &block)
      end
      put(key, new_value)
    end

    # Return a new `Hash` with the existing key/value associations, plus an association
    # between the provided key and value. If an equivalent key is already present, its
    # associated value will be replaced with the provided one.
    #
    # Avoid mutating objects which are used as keys. `String`s are an exception --
    # unfrozen `String`s which are used as keys are internally duplicated and
    # frozen.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2].store("C", 3)
    #   # => Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #
    # @param key [Object] The key to store
    # @param value [Object] The value to associate it with
    # @return [Hash]
    def store(key, value)
      put(key, value)
    end

    # Return a new `Hash` with the association for `key` removed. If `key` is not
    # present, return `self`.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].delete("B")
    #   # => Hamster::Hash["A" => 1, "C" => 3]
    #
    # @param key [Object] The key to remove
    # @return [Hash]
    def delete(key)
      derive_new_hash(@trie.delete(key))
    end

    # Call the block once for each key/value pair in this `Hash`, passing the key/value
    # pair as parameters. No specific iteration order is guaranteed (but the order will
    # be stable for any particular `Hash`.)
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].each { |k, v| puts "k=#{k} v=#{v}" }
    #
    #   k=A v=1
    #   k=B v=2
    #   k=C v=3
    #   # => Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #
    # @return [self]
    def each(&block)
      return to_enum if not block_given?
      @trie.each(&block)
      self
    end
    alias :each_pair :each

    # Call the block once for each key/value pair in this `Hash`, passing the key/value
    # pair as parameters. Iteration order will be the opposite of {#each}.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].reverse_each { |k, v| puts "k=#{k} v=#{v}" }
    #
    #   k=C v=3
    #   k=B v=2
    #   k=A v=1
    #   # => Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #
    # @return [self]
    def reverse_each(&block)
      return enum_for(:reverse_each) if not block_given?
      @trie.reverse_each(&block)
      self
    end

    # Call the block once for each key/value pair in this `Hash`, passing the key as a
    # parameter.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].each_key { |k| puts "k=#{k}" }
    #
    #   k=A
    #   k=B
    #   k=C
    #   # => Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #
    # @return [self]
    def each_key
      return enum_for(:each_key) if not block_given?
      @trie.each { |k,v| yield k }
      self
    end

    # Call the block once for each key/value pair in this `Hash`, passing the value as a
    # parameter.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].each_value { |v| puts "v=#{v}" }
    #
    #   v=1
    #   v=2
    #   v=3
    #   # => Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #
    # @return [self]
    def each_value
      return enum_for(:each_value) if not block_given?
      @trie.each { |k,v| yield v }
      self
    end

    # Call the block once for each key/value pair in this `Hash`, passing the key/value
    # pair as parameters. The block should return a `[key, value]` array each time.
    # All the returned `[key, value]` arrays will be gathered into a new `Hash`.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.map { |k, v| ["new-#{k}", v * v] }
    #   # => Hash["new-C" => 9, "new-B" => 4, "new-A" => 1]
    #
    # @return [Hash]
    def map
      return enum_for(:map) unless block_given?
      return self if empty?
      self.class.new(super, &@default)
    end
    alias :collect :map

    # Return a new `Hash` with all the key/value pairs for which the block returns true.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.select { |k, v| v >= 2 }
    #   # => Hamster::Hash["B" => 2, "C" => 3]
    #
    # @return [Hash]
    def select(&block)
      return enum_for(:select) unless block_given?
      derive_new_hash(@trie.select(&block))
    end
    alias :find_all :select
    alias :keep_if  :select

    # Yield `[key, value]` pairs until one is found for which the block returns true.
    # Return that `[key, value]` pair. If the block never returns true, return `nil`.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.find { |k, v| v.even? }
    #   # => ["B", 2]
    #
    # @return [Array]
    def find
      return enum_for(:find) unless block_given?
      each { |entry| return entry if yield entry }
      nil
    end
    alias :detect :find

    # Return a new `Hash` containing all the key/value pairs from this `Hash` and
    # `other`. If no block is provided, the value for entries with colliding keys
    # will be that from `other`. Otherwie, the value for each duplicate key is
    # determined by called the block with the key, its value in this `Hash`, and
    # its value in `other`.
    #
    # `other` can be a `Hamster::Hash`, a built-in Ruby `Hash`, or any `Enumerable`
    # object which yields `[key, value]` pairs.
    #
    # @example
    #   h1 = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h2 = Hamster::Hash["C" => 70, "D" => 80]
    #   h1.merge(h2)
    #   # => Hamster::Hash["C" => 70, "A" => 1, "D" => 80, "B" => 2]
    #   h1.merge(h2) { |key, v1, v2| v1 + v2 }
    #   # => Hamster::Hash["C" => 73, "A" => 1, "D" => 80, "B" => 2]
    #
    # @param other [Enumerable] The collection to merge with
    # @yieldparam key [Object] The key which was present in both collections
    # @yieldparam my_value [Object] The associated value from this `Hash`
    # @yieldparam other_value [Object] The associated value from the other collection
    # @yieldreturn [Object] The value to associate this key with in the new `Hash`
    # @return [Hash]
    def merge(other)
      trie = if block_given?
        other.reduce(@trie) do |trie, (key, value)|
          if entry = trie.get(key)
            trie.put(key, yield(key, entry[1], value))
          else
            trie.put(key, value)
          end
        end
      else
        @trie.bulk_put(other)
      end

      derive_new_hash(trie)
    end

    # Return a {Vector} which contains all the `[key, value]` pairs in this `Hash`
    # as 2-element Arrays, either in their natural sorted order as determined by
    # `#<=>`, or if an optional block is supplied, by using the block as a comparator.
    # See `Enumerable#sort`.
    #
    # @example
    #   h = Hamster::Hash["Dog" => 1, "Elephant" => 2, "Lion" => 3]
    #   h.sort { |(k1, v1), (k2, v2)| k1.size  <=> k2.size }
    #   # => Hamster::Vector[["Dog", 1], ["Lion", 3], ["Elephant", 2]]
    #
    # @return [Vector]
    def sort
      Vector.new(super)
    end

    # Return a {Vector} which contains all the `[key, value]` pairs in this `Hash`
    # as 2-element Arrays. The order which the pairs will appear in is determined by
    # passing each pair to the code block to obtain a sort key object, and comparing
    # the sort keys using `#<=>`.
    # See `Enumerable#sort_by`.
    #
    # @example
    #   h = Hamster::Hash["Dog" => 1, "Elephant" => 2, "Lion" => 3]
    #   h.sort_by { |key, value| key.size }
    #   # => Hamster::Vector[["Dog", 1], ["Lion", 3], ["Elephant", 2]]
    #
    # @return [Vector]
    def sort_by
      Vector.new(super)
    end

    # Return a new `Hash` with the associations for all of the given `keys` removed.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.except("A", "C")  # => Hamster::Hash["B" => 2]
    #
    # @param keys [Array] The keys to remove
    # @return [Hash]
    def except(*keys)
      keys.reduce(self) { |hash, key| hash.delete(key) }
    end

    # Return a new `Hash` with only the associations for the `wanted` keys retained.
    # If any of the `wanted` keys are not present in this `Hash`, they will not be present
    # in the returned `Hash` either.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.slice("B", "C")  # => Hamster::Hash["B" => 2, "C" => 3]
    #
    # @param wanted [Array] The keys to retain
    # @return [Hash]
    def slice(*wanted)
      trie = Trie.new(0)
      wanted.each { |key| trie.put!(key, get(key)) if key?(key) }
      self.class.alloc(trie, @default)
    end

    # Return a {Vector} of the values which correspond to the `wanted` keys.
    # If any of the `wanted` keys are not present in this `Hash`, they will be skipped.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => 2, "C" => 3]
    #   h.values_at("B", "A")  # => Hamster::Vector[2, 1]
    #
    # @param wanted [Array] The keys to retrieve
    # @return [Vector]
    def values_at(*wanted)
      array = []
      wanted.each { |key| array << get(key) if key?(key) }
      Vector.new(array.freeze)
    end

    # Return a new {Set} populated with the keys from this `Hash`.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3, "D" => 2].keys
    #   # => Hamster::Set["D", "C", "B", "A"]
    #
    # @return [Set]
    def keys
      Set.alloc(@trie)
    end

    # Return a new {Vector} populated with the values from this `Hash`.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3, "D" => 2].values
    #   # => Hamster::Vector[2, 3, 2, 1]
    #
    # @return [Vector]
    def values
      Vector.new(each_value.to_a.freeze)
    end

    # Return a new `Hash` created by using our keys as values, and values as keys.
    # If there are multiple values which are equivalent (as determined by `#hash` and
    # `#eql?`), only one out of each group of equivalent values will be retained.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3, "D" => 2].invert
    #   # => Hamster::Hash[1 => "A", 3 => "C", 2 => "B"]
    #
    # @return [Hash]
    def invert
      pairs = []
      each { |k,v| pairs << [v, k] }
      self.class.new(pairs, &@default)
    end

    # Return a new {Vector} which is a one-dimensional flattening of this `Hash`.
    # If `level` is 1, all the `[key, value]` pairs in the hash will be concatenated
    # into one {Vector}. If `level` is greater than 1, keys or values which are
    # themselves `Array`s or {Vector}s will be recursively flattened into the output
    # {Vector}. The depth to which that flattening will be recursively applied is
    # determined by `level`.
    #
    # As a special case, if `level` is 0, each `[key, value]` pair will be a
    # separate element in the returned {Vector}.
    #
    # @example
    #   h = Hamster::Hash["A" => 1, "B" => [2, 3, 4]]
    #   h.flatten
    #   # => Hamster::Vector["A", 1, "B", [2, 3, 4]]
    #   h.flatten(2)
    #   # => Hamster::Vector["A", 1, "B", 2, 3, 4]
    #
    # @param level [Integer] The number of times to recursively flatten the `[key, value]` pairs in this `Hash`.
    # @return [Vector]
    def flatten(level = 1)
      return Vector.new(self) if level == 0
      array = []
      each { |k,v| array << k; array << v }
      array.flatten!(level-1) if level > 1
      Vector.new(array.freeze)
    end

    # Searches through the `Hash`, comparing `obj` with each key (using `#==`).
    # When a matching key is found, return the `[key, value]` pair as an array.
    # Return `nil` if no match is found.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].assoc("B")  # => ["B", 2]
    #
    # @param obj [Object] The key to search for (using #==)
    # @return [Array]
    def assoc(obj)
      each { |entry| return entry if obj == entry[0] }
      nil
    end

    # Searches through the `Hash`, comparing `obj` with each value (using `#==`).
    # When a matching value is found, return the `[key, value]` pair as an array.
    # Return `nil` if no match is found.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].rassoc(2)  # => ["B", 2]
    #
    # @param obj [Object] The value to search for (using #==)
    # @return [Array]
    def rassoc(obj)
      each { |entry| return entry if obj == entry[1] }
      nil
    end

    # Searches through the `Hash`, comparing `value` with each value (using `#==`).
    # When a matching value is found, return its associated key object.
    # Return `nil` if no match is found.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].key(2)  # => "B"
    #
    # @param value [Object] The value to search for (using #==)
    # @return [Object]
    def key(value)
      each { |entry| return entry[0] if value == entry[1] }
      nil
    end

    # Return a randomly chosen `[key, value]` pair from this `Hash`. If the hash is empty,
    # return `nil`.
    #
    # @example
    #   Hamster::Hash["A" => 1, "B" => 2, "C" => 3].sample
    #   # => ["C", 3]
    #
    # @return [Array]
    def sample
      @trie.at(rand(size))
    end

    # Return an empty `Hash` instance, of the same class as this one. Useful if you
    # have multiple subclasses of `Hash` and want to treat them polymorphically.
    # Maintains the default block, if there is one.
    #
    # @return [Hash]
    def clear
      if @default
        self.class.alloc(EmptyTrie, @default)
      else
        self.class.empty
      end
    end

    # Return true if `other` has the same type and contents as this `Hash`.
    #
    # @param other [Object] The collection to compare with
    # @return [Boolean]
    def eql?(other)
      return true if other.equal?(self)
      instance_of?(other.class) && @trie.eql?(other.instance_variable_get(:@trie))
    end

    # Return true if `other` has the same contents as this `Hash`. Will convert
    # `other` to a Ruby `Hash` using `#to_hash` if necessary.
    #
    # @param other [Object] The object to compare with
    # @return [Boolean]
    def ==(other)
      self.eql?(other) || (other.respond_to?(:to_hash) && to_hash.eql?(other.to_hash))
    end

    # See `Object#hash`.
    # @return [Integer]
    def hash
      keys.to_a.sort.reduce(0) do |hash, key|
        (hash << 32) - hash + key.hash + get(key).hash
      end
    end

    # Return the contents of this `Hash` as a programmer-readable `String`. If all the
    # keys and values are serializable as Ruby literal strings, the returned string can
    # be passed to `eval` to reconstitute an equivalent `Hash`. However, the default
    # block (if there is one) will be lost when doing this.
    #
    # @return [String]
    def inspect
      result = "#{self.class}["
      i = 0
      each do |key, val|
        result << ', ' if i > 0
        result << key.inspect << ' => ' << val.inspect
        i += 1
      end
      result << "]"
    end

    # Allows this `Hash` to be printed at the `pry` console, or using `pp` (from the
    # Ruby standard library), in a way which takes the amount of horizontal space on
    # the screen into account, and which indents nested structures to make them easier
    # to read.
    #
    # @private
    def pretty_print(pp)
      pp.group(1, "#{self.class}[", "]") do
        pp.breakable ''
        pp.seplist(self, nil) do |key, val|
          pp.group do
            key.pretty_print(pp)
            pp.text ' => '
            pp.group(1) do
              pp.breakable ''
              val.pretty_print(pp)
            end
          end
        end
      end
    end

    # Convert this `Hamster::Hash` to an instance of Ruby's built-in `Hash`.
    #
    # @return [::Hash]
    def to_hash
      output = {}
      each do |key, value|
        output[key] = value
      end
      output
    end
    alias :to_h :to_hash

    # Deeply convert to Ruby Hash.
    #
    # @return [::Hash]
    def to_ruby
      Hamster.to_ruby(self)
    end

    # @return [::Hash]
    # @private
    def marshal_dump
      to_hash
    end

    # @private
    def marshal_load(dictionary)
      @trie = Trie[dictionary]
    end

    private

    # Return a new `Hash` which is derived from this one, using a modified {Trie}.
    # The new `Hash` will retain the existing default block, if there is one.
    #
    def derive_new_hash(trie)
      if trie.equal?(@trie)
        self
      elsif trie.empty?
        if @default
          self.class.alloc(EmptyTrie, @default)
        else
          self.class.empty
        end
      else
        self.class.alloc(trie, @default)
      end
    end
  end

  # The canonical empty `Hash`. Returned by `Hamster.hash` and `Hash[]` when
  # invoked with no arguments; also returned by `Hash.empty`. Prefer using this
  # one rather than creating many empty hashes using `Hash.new`.
  #
  EmptyHash = Hamster::Hash.empty
end
