require 'rubygems'
require 'minitest/spec'
require 'patricia_tree'

# Note: There's a 4-case theme in these tests for storage, deletion,
# and retrieval -- you can find it better described in PatriciaTree's
# code.

# Note: It's okay for this code to verify the structural integrity of the
# tree, since there are some small cases (e.g. deletion) where we want to
# verify the tree is as small as possible.

MiniTest::Unit.autorun

describe Collections::PatriciaTree do
  before do
    @unlocked_tree = Collections::PatriciaTree.new
    @locked_tree = Collections::PatriciaTree.new(true)
    @tree = Collections::PatriciaTree.new
    @tree.store("AB", 1)   
    @tree.store("ABBB", 2)      
    @tree.store("AAA", 3)
  end

  describe 'instantiation' do 
    it 'creates an unlocked, empty tree' do
      @unlocked_tree.children.size.must_equal 0
      @unlocked_tree.value.must_be_nil
      @unlocked_tree.edge_sequence.size.must_equal 0
      @unlocked_tree.locked?.must_equal false
      @unlocked_tree.empty?.must_equal true
    end

    it 'creates a locked, empty tree' do
      @locked_tree.children.size.must_equal 0
      @locked_tree.value.must_be_nil
      @locked_tree.edge_sequence.size.must_equal 0
      @locked_tree.locked?.must_equal true
      @locked_tree.empty?.must_equal true
    end
    
    it 'creates a small tree' do
      @tree.children.size.must_equal 1
      @tree.value.must_be_nil
      @tree.edge_sequence.size.must_equal 0
      
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_ab = node_a.children["B"]
      node_ab.children.size.must_equal 1
      node_ab.value.must_equal 1
      node_ab.edge_sequence.must_equal ["B"]
      
      node_abbb = node_ab.children["B"]
      node_abbb.children.size.must_equal 0
      node_abbb.value.must_equal 2
      node_abbb.edge_sequence.must_equal ["B", "B"]
      
      node_aaa = node_a.children["A"]
      node_aaa.children.size.must_equal 0
      node_aaa.value.must_equal 3
      node_aaa.edge_sequence.must_equal ["A", "A"]
      
      @tree.empty?.must_equal false
    end
  end

  describe 'storage' do    
    # NOTE: Some tests involve more than one case, but do specify what they are
    # testing as the last case.
    it 'inserts an element into an empty tree' do 
      @unlocked_tree.store("A", 1)
      @unlocked_tree.children.size.must_equal 1
      @unlocked_tree.children["A"].edge_sequence.must_equal ["A"]
      @unlocked_tree.children["A"].value.must_equal 1
      @unlocked_tree.children["A"].children.size.must_equal 0
    end
    
    it 'stores an empty sequence successfully' do
      @unlocked_tree.store("", 1)     
      @unlocked_tree.edge_sequence.must_equal []
      @unlocked_tree.children.size.must_equal 0
      @unlocked_tree.value.must_equal 1
    end
    
    it 'deletes an element if nil is stored for an existing key' do
      # NOTE: This test is dependent on delete working properly 
      @tree.store("AB", nil)
      @tree.children.size.must_equal 1
      
      node_a = @tree.children["A"]
      node_a.edge_sequence.must_equal ["A"]
      node_a.value.must_be_nil
      node_a.children.size.must_equal 2
      
      node_aaa = node_a.children["A"]
      node_aaa.edge_sequence.must_equal ["A", "A"]
      node_aaa.value.must_equal 3
      node_aaa.children.size.must_equal 0
      
      node_bbbb = node_a.children["B"]
      node_bbbb.edge_sequence.must_equal ["B", "B", "B"]
      node_bbbb.value.must_equal 2
      node_bbbb.children.size.must_equal 0
    end
    
    it 'stores with key that shares no prefix with the keys in the tree (ends in case 1)' do
      @tree.store("Z", 10)
      @tree.children.size.must_equal 2
      @tree.children["Z"].edge_sequence.must_equal ["Z"]
      @tree.children["Z"].value.must_equal 10
      @tree.children["Z"].children.size.must_equal 0
    end
    
    it 'stores with key that shares a prefix with some keys in the tree such that no node splitting is required (ends in case 2)' do
      @tree.store("AZ", 10)
      @tree.children.size.must_equal 1
      
      node_a = @tree.children["A"]
      node_a.edge_sequence.must_equal ["A"]
      node_a.value.must_be_nil
      node_a.children.size.must_equal 3
      
      node_az = node_a.children["Z"]
      node_az.edge_sequence.must_equal ["Z"]
      node_az.value.must_equal 10
      node_az.children.size.must_equal 0
    end  
    
    it 'stores with a key that already exists (ends in case 3)' do
      @tree.store("AB", 10)
      @tree.children.size.must_equal 1
      
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_ab = node_a.children["B"]
      node_ab.children.size.must_equal 1
      node_ab.value.must_equal 10
      node_ab.edge_sequence.must_equal ["B"]
    end  
    
    it 'stores with a key that shares a prefix with some keys in the tree such that a node split is necessary (ends in case 4)' do
      @tree.store("ABBZ", 10)
      @tree.children.size.must_equal 1
      
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_ab = node_a.children["B"]
      node_ab.children.size.must_equal 1 
      node_ab.value.must_equal 1
      node_ab.edge_sequence.must_equal ["B"]
      
      node_abb = node_ab.children["B"] # This will be the node that was split, and as a result has its edge_sequence shortened a bit
      node_abb.children.size.must_equal 2 # One child is the remainder of the original sequence, the other is for what we just inserted
      node_abb.value.must_be_nil
      node_abb.edge_sequence.must_equal ["B"]
      
      node_abbb = node_abb.children["B"] # The rest of the original sequence
      node_abbb.children.size.must_equal 0
      node_abbb.value.must_equal 2
      node_abbb.edge_sequence.must_equal ["B"]
      
      node_abbz = node_abb.children["Z"] # The new node for our sequence we just stored
      node_abbz.children.size.must_equal 0
      node_abbz.value.must_equal 10
      node_abbz.edge_sequence.must_equal ["Z"]
    end
  end

  describe 'deletion by key' do
    it 'deletes the value at the root' do
      @unlocked_tree.store("", 1)
      @unlocked_tree.delete("").must_equal 1
    end
    
    it 'deletes keys that do not exist (combines cases 1 and 4)' do
      @tree.delete("").must_be_nil # Special empty case
      @tree.delete("Z").must_be_nil # Case 1
      @tree.delete("A").must_be_nil # We don't want the A node to get removed
      @tree.delete("ABB").must_be_nil # Case 4
      
      # Re-verify the tree (copied and pasted from the instantiation test!)
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_ab = node_a.children["B"]
      node_ab.children.size.must_equal 1
      node_ab.value.must_equal 1
      node_ab.edge_sequence.must_equal ["B"]
      
      node_abbb = node_ab.children["B"]
      node_abbb.children.size.must_equal 0
      node_abbb.value.must_equal 2
      node_abbb.edge_sequence.must_equal ["B", "B"]
      
      node_aaa = node_a.children["A"]
      node_aaa.children.size.must_equal 0
      node_aaa.value.must_equal 3
      node_aaa.edge_sequence.must_equal ["A", "A"]
    end
    
    it 'deletes with key that shares a prefix with some keys in the tree (combines cases 2 and 3)' do
      # NOTE: This operation results in a node merge to minimize the tree
      @tree.delete("AB").must_equal 1 # case 2 is traversing A, case 3 is deletion of B by exact match once we get to the A node
      
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_abbb = node_a.children["B"]
      node_abbb.children.size.must_equal 0
      node_abbb.value.must_equal 2
      node_abbb.edge_sequence.must_equal ["B", "B", "B"]
      
      node_aa = node_a.children["A"]
      node_aa.children.size.must_equal 0
      node_aa.value.must_equal 3
      node_aa.edge_sequence.must_equal ["A", "A"]
    end
  end
  
  describe 'deletion by prefix' do
    it 'deletes by prefix from the root' do
      @tree.delete_prefix("")
      @tree.children.size.must_equal 0
      @tree.value.must_be_nil
      @tree.edge_sequence.must_equal []
    end
    
    it 'deletes prefix that do not exist (case 1)' do
      @tree.delete_prefix("Z")
      
      # Re-verify the tree (copied and pasted from the instantiation test!)
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_ab = node_a.children["B"]
      node_ab.children.size.must_equal 1
      node_ab.value.must_equal 1
      node_ab.edge_sequence.must_equal ["B"]
      
      node_abbb = node_ab.children["B"]
      node_abbb.children.size.must_equal 0
      node_abbb.value.must_equal 2
      node_abbb.edge_sequence.must_equal ["B", "B"]
      
      node_aaa = node_a.children["A"]
      node_aaa.children.size.must_equal 0
      node_aaa.value.must_equal 3
      node_aaa.edge_sequence.must_equal ["A", "A"]
    end
    
    it 'deletes prefix that traverses one node and ends on an exact match (cases 2 and 3)' do
      # NOTE: Results in a merge
      @tree.delete_prefix("AB")
      @tree.children.size.must_equal 1
      
      node_aaa = @tree.children["A"]
      node_aaa.children.size.must_equal 0
      node_aaa.value.must_equal 3
      node_aaa.edge_sequence.must_equal ["A", "A", "A"]     
    end
    
    it 'deletes prefix that traverses one node and ends on a partial match (cases 2 and 4)' do
      @tree.store("ABBBZ", 100) # Give ABBB a child, since what we're about to do should eliminate that node and its children
      
      @tree.delete_prefix("ABB")
      @tree.children.size.must_equal 1
      
      node_a = @tree.children["A"]
      node_a.children.size.must_equal 2
      node_a.value.must_be_nil
      node_a.edge_sequence.must_equal ["A"]
      
      node_ab = node_a.children["B"]
      node_ab.children.size.must_equal 0
      node_ab.value.must_equal 1
      node_ab.edge_sequence.must_equal ["B"]
      
      node_aaa = node_a.children["A"]
      node_aaa.children.size.must_equal 0
      node_aaa.value.must_equal 3
      node_aaa.edge_sequence.must_equal ["A", "A"]   
    end
  end
  
  describe 'fetches by key' do
    does_not_exist = "Default value for non-existent keys"
    
    it 'fetches from the root (empty key)' do
      @tree.store("", 10)
      @tree.fetch("").must_equal 10
    end
    
    it 'fetches by keys that do not exist (cases 1 and 4)' do
      @tree.fetch("A").must_be_nil # Default return for no match is nil, so be sure that's working
      @tree.fetch("", does_not_exist).must_equal does_not_exist
      @tree.fetch("A", does_not_exist).must_equal does_not_exist
      @tree.fetch("AZ", does_not_exist).must_equal does_not_exist
      @tree.fetch("ABB", does_not_exist).must_equal does_not_exist # Case 4
    end
    
    it 'fetches by traversing at least one node and ends in a full match (cases 2 and 3)' do
      @tree.fetch("AB").must_equal 1
      @tree.fetch("ABBB").must_equal 2
      @tree.fetch("AAA").must_equal 3
    end
  end
  
  describe 'fetches by prefix' do
    it 'fetches the root node by prefix' do
      # NOTE: Assumes that the stuff below the root node is okay.
      @tree.store("", 100) 
      n = @tree.fetch_prefix("")
      n.wont_be_nil
      n.locked?.must_equal true
      n.children.size.must_equal @tree.children.size
      n.edge_sequence.must_equal []
      n.value.must_equal @tree.value
    end
    
    it 'fetches non-existent prefixes' do
      n1 = @tree.fetch_prefix("Z") # Case 1
      n1.wont_be_nil
      n1.locked?.must_equal true
      n1.empty?.must_equal true
      
      n2 = @tree.fetch_prefix("AZ") # Case 2, then case 1
      n2.wont_be_nil
      n2.locked?.must_equal true
      n2.empty?.must_equal true
    end
    
    it 'fetches by a prefix that is the same as a key in the tree, traversing a node and ending on its child (cases 2 and 3)' do
      n = @tree.fetch_prefix("AB")
      n.children.size.must_equal 1
      
      node_ab = n.children["A"]
      node_ab.children.size.must_equal 1
      node_ab.value = 1
      node_ab.edge_sequence = ["A", "B"]   
      
      node_abbb = node_ab.children["B"]
      node_abbb.children.size.must_equal 0
      node_abbb.value = 2
      node_abbb.edge_sequence = ["B", "B"]   
    end
    
    it 'fetches by a prefix that forces a node to be split, traversing a node and ending on a partial match (cases 2 and 4)' do
      n = @tree.fetch_prefix("ABB")
      n.children.size.must_equal 1
      
      node_abbb = n.children["A"]
      node_abbb.children.size.must_equal 0
      node_abbb.value = 2
      node_abbb.edge_sequence = ["A", "B", "B", "B"]
    end
  end
  
  describe 'key-value iteration' do
    it 'iterates over an empty tree' do
      h = {}
      @unlocked_tree.each { |k, v| h[k] = v }
      h.size.must_equal 0 
    end
    
    it 'iterates over a tree with a value in the root' do
      @unlocked_tree.store("", 100)
      h = {}
      @unlocked_tree.each { |k, v| h[k] = v }
      h.size.must_equal 1
      h["".split('')].must_equal 100
    end
    
    it 'iterates over a sizable tree' do
      h = {}
      @tree.each { |k, v| h[k] = v }
      h.size.must_equal 3
      h["AB".split('')].must_equal 1
      h["ABBB".split('')].must_equal 2
      h["AAA".split('')].must_equal 3
    end
  end
  
  describe 'value-only iteration' do
    it 'iterates over an empty tree' do
      a = []
      @unlocked_tree.each_value { |v| a << v }
      a.size.must_equal 0 
    end
    
    it 'iterates over a tree with a value in the root' do
      @unlocked_tree.store("", 100)
      a = []
      @unlocked_tree.each_value { |v| a << v }
      a.size.must_equal 1
      a.include?(100).must_equal true
    end
    
    it 'iterates over a sizable tree' do
      a = []
      @tree.each_value { |v| a << v }
      a.size.must_equal 3
      a.include?(1).must_equal true
      a.include?(2).must_equal true
      a.include?(3).must_equal true
    end
  end

  describe 'tree locking' do
    it 'forbids mutation of a locked tree' do
      proc { @locked_tree.delete_prefix("A") }.must_raise Collections::PatriciaTree::TreeLocked      
      proc { @locked_tree.delete("A")        }.must_raise Collections::PatriciaTree::TreeLocked
      proc { @locked_tree["A"] = 1           }.must_raise Collections::PatriciaTree::TreeLocked
    end
  end
end
