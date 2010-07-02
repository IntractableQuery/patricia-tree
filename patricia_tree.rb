# Note: This is nearly finished, but needs to be cleaned up a bit
#       and some functionality needs to be decided on.
#       You may assume you're using it under GPLv3.
#
# This is an implementation of of a Patricia (radix) tree:
#  http://en.wikipedia.org/wiki/Radix_tree
#
# This was created for use with MagLev, but perfectly fine to use in any other
# Ruby implementation.
#
# This type of tree is useful for performing prefix searches
# (e.g. "give me all strings starting with 'Bob'")
# since the tree is organized starting from the first sequence
# in a given key (the key might be a string, which is a sequence
# of characters) and "narrows down" as you descend the tree. 
#
# Because of the prefix-searching property, this data structure
# can be useful for indexing object fields in MagLev, giving
# you the same power you'd usually have with an RDBMS using a B-Tree 
# index on a text field, enabling efficient "LIKE 'ABCTEST%'" 
# prefix searches.  Note that MagLev can speed up such queries
# in a similar manner with indexes, but as of 2010-june-29, 
# sorted returns are not supported and there is a performance
# benefit in using this data structure over an equality index
# when there is a large data set that you only want the top N
# ordered results from.
# 
# The tree serves as a dictionary/map and is reasonably good 
# at conserving space, provided there is a fairly large number 
# of words/sequences that share common prefixes.
# 
# = To do =
# * like Hash, should we use a default value instead of nil ? this alters the way store() and other methods would work, so need to decide early
# * Adding in support later for deletion/insertion/fetching on the root node itself (an empty key) sort of invalidated some of the 4-case code; might need to be cleaned later
# * Put up a clearer license header
module Collections
  class PatriciaTree
    include Enumerable
    
    class TreeLocked < Exception
      def initialize
        super('this tree is locked; it cannot be modified unless a new copy of it is made')
      end
    end

    attr_accessor :edge_sequence, :value, :children

    # Initializes an empty tree.
    # When +locked+ is true, the tree cannot be modified.  Otherwise, the
    # tree can be modified.
    def initialize(locked=nil)
      # The "edge sequence" is the edge between us and our parent.
      # You may assume that this is always an instance of Array.
      @edge_sequence = []
      
      # A leaf node will contain a value, which is associated with the
      # key sequence.  Since interior nodes also have a value field, it
      # will always be nil.
      @value = nil
   
      # We have children.  The key is the first member of
      # the node's edge_sequence.
      @children = {}
      
      # @locked is set to true if modifying this node should be made
      # impossible -- be nil or false otherwise (although we externally
      # present it as only a boolean).
      # Note that @locked does not cascade downward; children nodes may be 
      # unlocked, although you should take care to protect them from external
      # modification.
      # Also, this is similar to freezing.  It's not called freezing because
      # semantically, copying objects doesn't normally unfreeze them -- when
      # we copy, we unlock.
      @locked = locked
    end

    # Behaves as a normal shallow copy with the following exceptions:
    #  * The edge_sequence array is duped
    #  * The children hash is duped
    #  * The locked field is reset; a cloned tree node is okay to modify since it can't destablize another tree
    def initialize_copy(source)  
       super         
       @edge_sequence = @edge_sequence.dup
       @children = @children.dup
       @locked = nil
    end 
    
    def locked?
      @locked == true
    end

    # Accepts a +key_sequence+ and looks for a child node that
    # matches the start of that sequence (that is, the first member)
    # and returns two values: the node that matched and the 
    # length of the match with the child node.
    # If there is no matching child node, then nil is returned for
    # both of those values.
    # Do not feed this a +key_sequence+ with zero length.
    def find_child(key_sequence)
      child = nil
      match_length = nil
      child = @children[key_sequence[0]]
      unless child.nil? then
        match_length = 1 # We already checked first member of sequence
        (1...key_sequence.size).each { |n|
          if key_sequence[n] != child.edge_sequence[n] then
            # We stopped matching the edge sequence, so we are done
            break
          else
            match_length = n + 1
          end
        }
      end
      return child, match_length
    end
    private :find_child

    # Takes +key_sequence+, an object that responds to two methods:
    #  * [] - An indexing method accepting an integer and returning the element at that index.  Furthermore, the element it returns should respond to "<=>" and "==" for object comparison.
    #  * size - Returns the size of the sequence.
    # Note that String satisfies these conditions.  You may notice that prior to Ruby 1.9, String's [] method doesn't work as
    # desired -- do not worry about this, since String is a special case and will be handled properly here.
    #
    # The key sequence is used to uniquely identify +value+, which will be
    # associated with +key_sequence+, much like a hash table.
    # As you might expect, you will overwrite any existing key sequence
    # with the new value.  Storing a nil value will effectively delete
    # the key sequence from this tree. 
    # 
    # Note that trying to store a value in a locked tree results in a TreeLocked exception.
    def store(key_sequence, value=nil)
      # Some general observations from benchmarking this method:
      #   * split('') is faster than scan(/./) for maglev/mri1.9
      #   * Switching the [index] method to a [index,length] requirement for key_sequence
      #     in order to prettify code here has a significant performance impact unless
      #     you are accepting key_sequence as a string (and never converting it to an
      #     array).  Put another way, pulling substrings from a string is faster than pulling
      #     subarrays from an array -- the effect is most pronounced in maglev, which seems to
      #     handle substring derivation much faster than mri.
      #   * Not benchmarking related, but the real reason we convert key_sequence to an Array
      #     if it was a String is because before ruby 1.9, [] returns an ASCII code instead of a char
      key_sequence = key_sequence.split('') if key_sequence.kind_of? String
      raise TreeLocked if @locked
      delete key_sequence if value.nil?
      if key_sequence.size == 0 then
        @value = value # Special case after-thought: we do want to store empty sequences
      end
      return if value.nil? or key_sequence.size == 0 

      # Inspect children and do our best to match the given key sequence
      # to one of them for as long a length as possible.
      #best_match = nil # Holds the child with the best matching prefix
      #match_length = nil # Holds the length of the match in that child
      
      # First, inspect the children and find one that we can use
      best_match, match_length = find_child(key_sequence)
      
      # Second, work with the resulting best_match child and match_length
      # to cover one of the following cases:
      #  (1) best_match is nil, indicating we need to make a new child 
      #  (2) best_match is non-nil, match_length == best_match.edge_sequence.size, but key_sequence.size > best_match.edge_sequence.size, indicating that we need to remove the common prefix from the key (that is, best_match.edge_sequence) to create a new sub-key to use in a recursive insert further down the tree
      #  (3) best_match is non-nil, match_length == best_match.edge_sequence.size, and key_sequence.size == best_match.edge_sequence.size, indicating that we can store the value in best_match
      #  (4) best_match is non-nil, match_length < key_sequence.size, indicating that we need to split the best_match node and give it two children
      if best_match.nil? then
        # Case 1
        new_child = PatriciaTree.new
        new_child.edge_sequence = []
        (0...key_sequence.size).each { |n| new_child.edge_sequence << key_sequence[n] }
        new_child.value = value
        @children[key_sequence[0]] = new_child
      elsif match_length == best_match.edge_sequence.size then 
        # Either case 2 or 3
        if key_sequence.size > best_match.edge_sequence.size then
          # Case 2
          # Build a new partial key that contains all the sequence members that come
          # after the ones already found in best_match.edge_sequence
          new_key = []
          (match_length...key_sequence.size).each { |n| 
            new_key << key_sequence[n] 
          }
          best_match.store(new_key, value)
        else # now we know key_sequence.size == best_match.edge_sequence.size
          # Case 3
          best_match.value = value
        end
      else
        # Case 4
        # We're about to modify best_match in-place, so preserve some of its fields we need later
        best_edge_sequence = best_match.edge_sequence
        best_children = best_match.children
        best_value = best_match.value

        # Build a partial key to be used for a new node to replace
        # the best_match node (it represents the longest prefix that we were able
        # to match just now, of best_match length). 
        root_key = []
        (0...match_length).each { |n| root_key << key_sequence[n] }
        best_match.edge_sequence = root_key # This is okay to do, since the parent of best_match can't possibly have a child that conflicts with this slightly generalized prefix (that is, all we did is shortened edge_sequence)
        best_match.children = {}
        best_match.value = nil

        # Now we need a node under best_match (with a partial key representing the rest of best_edge_sequence) 
        # that we will move the "old" best_match down to.
        sub_key = []
        (match_length...best_edge_sequence.size).each { |n| sub_key << best_edge_sequence[n] }
        sub_tree = PatriciaTree.new
        sub_tree.edge_sequence = sub_key
        sub_tree.children = best_children
        sub_tree.value = best_value
        best_match.children[sub_key[0]] = sub_tree 
        
        # Finally, we need another node under best_match (with a partial key representing the rest
        # of key_sequence, which we know doesn't match the rest of best_edge_sequence) that stores
        # our value.
        new_key = []
        (match_length...key_sequence.size).each { |n| new_key << key_sequence[n] }
        new_tree = PatriciaTree.new
        new_tree.edge_sequence = new_key
        new_tree.value = value
        best_match.children[new_key[0]] = new_tree 
      end
    end  
    alias :[]= :store
    
    # Prints the tree out (useful for debugging).
    def print_tree(depth=0)
      prefix = "  " * depth
      edge_seq_str = ""
      (0...@edge_sequence.size).each { |n|
        edge_seq_str += @edge_sequence[n].to_s 
      }
      puts prefix + "'#{edge_seq_str}'" + (value.nil? ? "" : " value=#{value}")
      @children.each { |key, child|
        child.print_tree(depth+1)
      }
    end

    # Removes the key-value pair for the given +key_sequence+.
    # Returns the value that was removed, or nil if there was
    # no entry in the tree for the given key sequence (that is,
    # no removal took place).
    # Note that trying to delete from a locked tree results in a TreeLocked exception.
    def delete(key_sequence)
      remove(key_sequence, false)
    end

    # Given a prefix, +start_sequence+, all key-value pairs with
    # a key starting with +start_sequence+ will be removed from
    # the tree.
    # Note that trying to delete from a locked tree results in a TreeLocked exception.
    def delete_prefix(start_sequence)
      remove(start_sequence, true)
    end

    # This performs removal of key-value pair(s) from the tree
    # by either using a direct match with +key_sequence+ (+is_prefix+ is false) or
    # by using +key_sequence+ as a prefix that deletes 0 or more keys
    # from the tree (+is_prefix+ is true).
    # This will return the value that was removed or nil if no value
    # was removed (the return value is only provided when +is_prefix+ is false,
    # otherwise the return value is undefined and you shouldn't use it).
    def remove(key_sequence, is_prefix)
      val = nil
      key_sequence = key_sequence.split('') if key_sequence.kind_of? String
      raise TreeLocked if @locked
      if key_sequence.size == 0 then
        # Special case as an after-thought: we need to be able to remove the root
        val = @value
        @value = nil
        @children = {} if is_prefix # Wipe children      
        return val
      end
      
      best_match, match_length = find_child(key_sequence)

      # Logic here is quite similar to store() and its 4 cases
      if best_match.nil? then
        # Case 1: Nothing to do; no match
      elsif match_length == best_match.edge_sequence.size then
        if key_sequence.size > best_match.edge_sequence.size then
          # Case 2
          # Build a new partial key that contains all the sequence members that come
          # after the ones already found in best_match.edge_sequence
          new_key = []
          (match_length...key_sequence.size).each { |n|
            new_key << key_sequence[n]
          }
          val = best_match.remove(new_key, is_prefix)
        else # now we know key_sequence.size == best_match.edge_sequence.size
          # Case 3: Perfect match
          # NOTE: We can get a perfect match on a "splitting node" that holds no
          # value but just branches off in to two or more subtrees.  It's fine to 
          # "remove" it since it has no effect (the value will always be nil). 
          val = best_match.value
          best_match.value = nil
          # We should delink the child (best_match) if it has no children of its own or we're doing a prefix delete
          @children.delete(key_sequence[0]) if best_match.leaf? or is_prefix
          # Evaluate best_match's state; changing the value may have opened up a merge opportunity
          best_match.check_merge
        end
      else
        # Case 4: We matched only the first few members of the sequence 'best_match' stores, so
        # we only take action and wipe out child if we are doing a prefix delete.
        @children.delete(key_sequence[0]) if is_prefix
      end

      # Evaluate our own state; removal activity in a child may have opened up a merge opportunity
      check_merge
      
      val
    end
    protected :remove

    # Fetches a value associated with the key +key_sequence+, or returns
    # +default+ if there was no result (note that +default+ will be nil
    # if you do not set it, meaning a nil would be returned).
    def fetch(key_sequence, default=nil)  
      val = find(key_sequence, false)
      val = default if val.nil?
      val
    end
    alias :[] :fetch
    
    # Fetches a PatriciaTree that contains all key-value pairs in this tree
    # where the key starts with +start_sequence+.  If nothing could be found,
    # then an empty tree will be returned.
    # Note that the returned node will be locked, meaning you cannot modify it.  
    def fetch_prefix(start_sequence)
      node = find(start_sequence, true)
      node = PatriciaTree.new(true) if node.nil? # empty locked tree
      node
    end
     
    # This takes +prefix+, an array representing the start of a key, and uses
    # it to build a new PatriciaTree instance with this node that is rooted
    # at that prefix.  When +prefix+ is nil, this node itself will be
    # copied directly rather than trying to create a new tree.
    # In other words, it will tack on the given +prefix+ sequence (conformant
    # to the same rules laid out for +key_sequence+ in +store+) to the tree
    # and return a node representing the tree.
    # The returned tree will be locked, meaning it cannot be modified.
    def as_root_from_prefix(prefix=nil)
      # Build tree root (locked)
      root = PatriciaTree.new(true)
      
      if prefix.nil? then
        # Special case: we want to include the root
        root.value = @value
        root.children = @children
        return root
      end
      
      # Build prefix node that inherits the edge_sequence from this node, but
      # also tacks on the prefix sequence we were given.
      pnode = PatriciaTree.new
      new_seq = prefix.dup
      (0...@edge_sequence.size).each { |n| new_seq << @edge_sequence[n] }
      pnode.edge_sequence = new_seq
      pnode.value = @value
      pnode.children = @children
      root.children[prefix[0]] = pnode
      
      root    
    end
    
    # If +is_prefix+ is false, then +key_sequence+ is used to retrieve and
    # return the value associated with the given key (or nil if there is none).
    # When +is_prefix+ is true, a PatriciaTree instance is returned that
    # is the root for nodes with keys starting with +key_sequence+.
    # The +prefix+ parameter is optional Array and specifies a prefix to put
    # on the returned node (this essentially defines its edge_sequence).
    # If no node(s) are found, then nil will be returned.
    #
    # Note: This makes no guarantee the PatriciaTree node(s) are even in this
    # tree.  The returned node will be locked.
    def find(key_sequence, is_prefix, prefix=[])
      key_sequence = key_sequence.split('') if key_sequence.kind_of? String
      if key_sequence.size == 0 then
        # After-thought: handle case of returning root
        if is_prefix then
          return as_root_from_prefix(nil)
        else
          return @value
        end
      end
      
      best_match, match_length = find_child(key_sequence)

      val = nil
      # Branching here is quite similar to store() (and was copied over shamelessly from remove())
      if best_match.nil? then
        # Case 1: Nothing to do; no match
      elsif match_length == best_match.edge_sequence.size then
        if key_sequence.size > best_match.edge_sequence.size then
          # Case 2
          # Build a key that will be the "prefix" and one that will be a new 
          # partial key that contains all the sequence members that come
          # after the ones already found in best_match.edge_sequence
          new_prefix = prefix.dup
          (0...match_length).each { |n| new_prefix << key_sequence[n] }
          new_key = []
          (match_length...key_sequence.size).each { |n| new_key << key_sequence[n] }
          val = best_match.find(new_key, is_prefix, new_prefix)
        else # now we know key_sequence.size == best_match.edge_sequence.size
          # Case 3: Perfect match
          if is_prefix then
            # We return the equivalent of best_match node
            val = best_match.as_root_from_prefix(prefix)
          else
            val = best_match.value
          end
        end
      else
        # Case 4: We only want to return a result if we're doing a prefix search
        # since we have an incomplete match on best_match.
        val = best_match.as_root_from_prefix(prefix) if is_prefix
      end

      val
    end
    protected :find

    # This has been unimplemented for now since it's not an especially useful
    # method, but here's a reminder if it is desired in the future:
    # If a tree is @locked, you will need to ensure the user cannot mutate
    # descendants of the locked root node from here (since when a tree is locked, 
    # the only thing preventing its mutation is inability to use the mutation
    # methods in the root node).  Locking descendant nodes automatically during
    # iteration won't work, since the nodes may be a part of a different tree.
    # One way to solve this issue is to construct a new node each time that is
    # already locked and contains a copy of the other fields in the node
    # being iterated over. 
    #def each_node()
    #end

    # Visits each key-value pair rooted at this node (in a lowest-to-highest order -- 
    # e.g. for strings, alphabetic order) and passes it to 
    # the given block. When +ordered+ is true, iteration will take place
    # in alphabetical/sorted order by key -- when false, the iteration order is
    # arbitrary (and slightly faster).
    # +prefix+ can be used to specify an optional set of elements to prefix all 
    # returned keys by -- the majority of the time, you won't need this.  
    # Note that keys will be formed as Arrays of elements, so don't expect
    # to get a String back as a key if you had inserted a String originally.
    # Note that the key is provided as a new Array, so you are free to mutate
    # it with no ill side effects.
    def each(ordered=true, prefix=[], &block)
      cur_prefix = prefix.dup
      (0...@edge_sequence.size).each { |n| cur_prefix << @edge_sequence[n] } 

      block.call(cur_prefix.dup, @value) unless @value.nil? #or @edge_sequence.size == 0
      keys = @children.keys
      keys = keys.sort if ordered
      keys.each { |ckey| 
        @children[ckey].each(ordered, cur_prefix, &block)
      } 
    end

    # Behaves like +each+, but only passes a value to the block.
    # When +ordered+ is true, iteration over values occurs in alphabetic/sorted
    # order by key-- when false, iteration order is arbitrary (and slightly faster).
    def each_value(ordered=true, &block)
      # We can save a slight bit of time by duplicating logic from each(), but
      # skipping the part where we keep building up a prefix.
      block.call(@value) unless @value.nil? #or @edge_sequence.size == 0
      keys = @children.keys
      keys = keys.sort if ordered
      keys.each { |ckey|
        @children[ckey].each_value(&block)
      }
    end
    
    # Behaves like +each+, but only passes a key to the block
    # When +ordered+ is true, iteration over values occurs in alphabetic/sorted
    # order -- when false, iteration order is arbitrary (and slightly faster).
    def each_key(ordered=true, &block)
      each(ordered) { |k, v| block.call(k) }
    end
    
    # Returns all key-value pairs in this tree as a Hash instance.  Note that
    # this requires iteration over all nodes in the tree to construct 
    # the hash, which can be expensive for large trees.
    # Note that the key is provided as a new Array, so you are free to mutate
    # it with no ill side effects.
    def to_hash
      hash = {}
      each(false) { |k, v| hash[k] = v }
      hash
    end
    
    # Returns all the keys in this tree as an Array.
    # When +ordered+ is true, the keys will be in alphabetic/sorted order,
    # otherwise they are in arbitrary order (but construction of the array is
    # faster).
    # Note that this requires iteration over all nodes in the tree to construct 
    # the array, which can be expensive for large trees.  You might consider
    # using +each+ or +each_key+ instead.
    def keys(ordered=true)
      array = []
      each_key(ordered) { |k| array << k }
      array
    end
    
    # Returns all of the values in this tree as an Array.
    # When +ordered+ is true, the values will be in alphabetic/sorted order by
    # their key, otherwise they are in an arbitrary order (but construction of 
    # the array is faster).
    # Note that this requires iteration over all nodes in the tree to construct 
    # the array, which can be expensive for large trees.  You might consider
    # using +each+ or +each_value+ instead.
    def values(ordered=true)
      array = []
      each_value(ordered) { |v| array << v }
      array
    end

    # Unless this is the root node of the tree, this checks to see if we can merge 
    # with a single child (this preserves the smallest-possible edge_sequences for each node).
    def check_merge
      if not @edge_sequence.size == 0 and (@children.size == 1 and @value.nil?) then
        # Merge in to our only child by appending its edge sequence and copying its fields;
        # this node no longer has a reason to exist separately.
        child = @children[@children.keys[0]]
        new_seq = []
        (0...@edge_sequence.size).each { |n| new_seq << @edge_sequence[n] }
        (0...child.edge_sequence.size).each { |n| new_seq << child.edge_sequence[n] }
        @edge_sequence = new_seq
        @children = child.children
        @value = child.value
      end
    end
    protected :check_merge

    # Determines if this node's edge_sequence in combination with its
    # ancestor's edge_sequences constitutes a full key.
    def terminal? 
      not @value.nil?
    end

    # Determines if this is a leaf node.
    def leaf?
      @children.empty?
    end
    
    # Determines if the tree rooted at this node has key-element pairs in it.
    def empty? 
      @value.nil? and @children.size == 0
    end
  end
end

