##
# A Foreign Function Interface used to bind C libraries to ruby.

module FFI

  #  Specialised error classes
  class TypeError < RuntimeError; end

  class NotFoundError < RuntimeError
    def initialize(function, library)
      super("Function '#{function}' not found! (Looking in '#{library or 'this process'}')")
    end
  end

  # Shorthand for the current process, i.e. all code that
  # the process image itself contains. In addition to the
  # Rubinius codebase, this also includes libc etc.
  #
  # Use this constant instead of nil directly.
  #
  USE_THIS_PROCESS_AS_LIBRARY = nil

  TypeDefs = LookupTable.new

  class << self

    def add_typedef(current, add)
      if current.kind_of? Fixnum
        code = current
      else
        code = FFI::TypeDefs[current]
        raise TypeError, "Unable to resolve type '#{current}'" unless code
      end

      FFI::TypeDefs[add] = code
    end

    def find_type(name)
      code = FFI::TypeDefs[name]
      raise TypeError, "Unable to resolve type '#{name}'" unless code
      return code
    end

    def create_backend(library, name, args, ret)
      Ruby.primitive :nativefunction_bind
      raise NotFoundError.new(name, library)
    end

    # Internal function, should not be used directly.
    # See Module#attach_function.
    #
    # TODO: Is this necessary at all? When would we ever
    #       create an unattached method (not a Method)?
    def create_function(library, name, args, ret)
      i = 0
      tot = args.size

      # We use this instead of map or each because it's really early, map
      # isn't yet available.
      while i < tot
        args[i] = find_type(args[i])
        i += 1
      end
      cret = find_type(ret)

      if library.respond_to?(:each) and !library.kind_of? String
        library.each do |lib|
          lib = setup_ld_library_path(lib) if lib
          func = create_backend(lib, name, args, cret)
          return func if func
        end
        return nil
      else
        library = setup_ld_library_path(library) if library
        create_backend(library, name, args, cret)
      end
    end

    # Setup the LD_LIBRARY_PATH
    # @todo   Not using LTDL currently.
    def setup_ld_library_path(library)
      # If we have a specific reference to the library, we load it here
      specific_library = config("ld_library_path.#{library}")
      library = specific_library if specific_library

      # This adds general paths to the search
      if path = config("ld_library_path.default")
        ENV['LTDL_LIBRARY_PATH'] = [ENV['LTDL_LIBRARY_PATH'], path].compact.join(":")
      end

      library
    end

  end

  # Converts a Rubinius Object
  add_typedef TYPE_OBJECT,  :object

  # Converts a char
  add_typedef TYPE_CHAR,    :char

  # Converts an unsigned char
  add_typedef TYPE_UCHAR,   :uchar

  # Converts a short
  add_typedef TYPE_SHORT,   :short

  # Converts an unsigned short
  add_typedef TYPE_USHORT,  :ushort

  # Converts an int
  add_typedef TYPE_INT,     :int

  # Converts an unsigned int
  add_typedef TYPE_UINT,    :uint

  # Converts a long
  add_typedef TYPE_LONG,    :long

  # Converts an unsigned long
  add_typedef TYPE_ULONG,   :ulong

  # Converts a long long
  add_typedef TYPE_LL,      :long_long

  # Converts an unsigned long long
  add_typedef TYPE_ULL,     :ulong_long

  # Converts a float
  add_typedef TYPE_FLOAT,   :float

  # Converts a double
  add_typedef TYPE_DOUBLE,  :double

  # Converts a pointer to opaque data
  add_typedef TYPE_PTR,     :pointer

  # For when a function has no return value
  add_typedef TYPE_VOID,    :void

  # Converts NULL-terminated C strings
  add_typedef TYPE_STRING,  :string

  # Converts the current Rubinius state
  add_typedef TYPE_STATE,   :state

  # Use strptr when you need to free the result of some operation.
  add_typedef TYPE_STRPTR,  :strptr
  add_typedef TYPE_STRPTR,  :string_and_pointer

  # Use for a C struct with a char [] embedded inside.
  add_typedef TYPE_CHARARR, :char_array

  TypeSizes = LookupTable.new
  TypeSizes[1] = :char
  TypeSizes[2] = :short
  TypeSizes[4] = :int
  TypeSizes[8] = Rubinius::L64 ? :long : :long_long

  # Load all the platform dependent types

  Rubinius::RUBY_CONFIG.section("rbx.platform.typedef.") do |key, value|
    add_typedef(find_type(value.to_sym), key.substring(21, key.length).to_sym)
  end

  def self.size_to_type(size)
    if sz = TypeSizes[size]
      return sz
    end

    # Be like C, use int as the default type size.
    return :int
  end

  def self.config(name)
    Rubinius::RUBY_CONFIG["rbx.platform.#{name}"]
  end

  def self.config_hash(name)
    vals = { }
    section = "rbx.platform.#{name}."
    Rubinius::RUBY_CONFIG.section section do |key,value|
      vals[key.substring(section.size, key.length)] = value
    end
    vals
  end

end

class Module

  # Set which library or libraries +attach_function+ should
  # look in. By default it only searches for the function in
  # the current process. If you want to specify this as one
  # of the locations, add FFI::USE_THIS_PROCESS_AS_LIBRARY.
  # The libraries are tried in the order given.
  #
  def set_ffi_lib(*names)
    @ffi_lib = names
  end

  # Attach C function +name+ to this module.
  #
  # If you want to provide an alternate name for the module function, supply
  # it after the +name+, otherwise the C function name will be used.#
  #
  # After the +name+, the C function argument types are provided as an Array.
  #
  # The C function return type is provided last.
  #
  def attach_function(name, a3, a4, a5=nil)
    if a5
      mname = a3
      args = a4
      ret = a5
    else
      mname = name.to_sym
      args = a3
      ret = a4
    end

    func = FFI.create_function @ffi_lib, name, args, ret

    # Error handling does not work properly so avoid it for now.
    if !func
      STDOUT.write "*** ERROR: Native function "
      STDOUT.write name.to_s
      STDOUT.write " from "
      if @ffi_lib
        STDOUT.write @ffi_lib.to_s
      else
        STDOUT.write "this process"
      end
      STDOUT.write " could not be found or linked.\n"

      if Rubinius::RUBY_CONFIG["rbx.ffi.soft_fail"]
        STDOUT.write "***        Proceeding because rbx.ffi.soft_fail is set. Program may fail later.\n"
        return nil
      else
        STDOUT.write "***        If you want to try to work around this problem, you may set configuration\n"
        STDOUT.write "***        variable rbx.ffi.soft_fail.\n"
        STDOUT.write "***        Exiting.\n"
        Process.exit 1
      end
    end

    metaclass.method_table[mname] = func
    return func
  end

end

##
# MemoryPointer is Rubinius's "fat" pointer class. It represents an actual
# pointer, in C language terms, to an address in memory. They're called
# fat pointers because the MemoryPointer object is an wrapper around
# the actual pointer, the Rubinius runtime doesn't have direct access
# to the raw address.
#
# This class is used extensively in FFI usage to interface with various
# parts of the underlying system. It provides a number of operations
# for operating on the memory that is pointed to. These operations effectively
# give Rubinius the cast/read capabilities available in C, but using
# high level methods.
#
# MemoryPointer objects can be put in autorelease mode. In this mode,
# when the GC cleans up a MemoryPointer object, the memory it points
# to is passed to free(3), releasing the memory back to the OS.
#
# NOTE: MemoryPointer exposes direct, unmanaged operations on any
# memory. It therefore MUST be used carefully. Reading or writing to
# invalid address will cause bus errors and segmentation faults.

class MemoryPointer

  # call-seq:
  #   MemoryPointer.new(num) => MemoryPointer instance of <i>num</i> bytes
  #   MemoryPointer.new(sym) => MemoryPointer instance with number
  #                             of bytes need by FFI type <i>sym</i>
  #   MemoryPointer.new(obj) => MemoryPointer instance with number
  #                             of <i>obj.size</i> bytes
  #   MemoryPointer.new(sym, count) => MemoryPointer instance with number
  #                             of bytes need by length-<i>count</i> array
  #                             of FFI type <i>sym</i>
  #   MemoryPointer.new(obj, count) => MemoryPointer instance with number
  #                             of bytes need by length-<i>count</i> array
  #                             of <i>obj.size</i> bytes
  #   MemoryPointer.new(arg) { |p| ... }
  #
  # Both forms create a MemoryPointer instance. The number of bytes to
  # allocate is either specified directly or by passing an FFI type, which
  # specifies the number of bytes needed for that type.
  #
  # The form without a block returns the MemoryPointer instance. The form
  # with a block yields the MemoryPointer instance and frees the memory
  # when the block returns. The value returned is the value of the block.

  def self.new(type, count=nil, clear=true)
    if type.kind_of? Fixnum
      size = type
    elsif type.kind_of? Symbol
      type = FFI.find_type type
      size = FFI.type_size(type)
    else
      size = type.size
    end

    if count
      total = size * count
    else
      total = size
    end

    ptr = Platform::POSIX.malloc total
    ptr.total = total
    ptr.type_size = size
    Platform::POSIX.memset ptr, 0, total if clear

    if block_given?
      begin
        value = yield ptr

        return value
      ensure
        ptr.free
      end
    else
      ptr.autorelease = true
      ptr
    end
  end

  def clone
    other = Platform::POSIX.malloc total
    other.total = total
    other.type_size = type_size
    Platform::POSIX.memcpy other, self, total
    other
  end

  def dup
    other = Platform::POSIX.malloc total
    other.total = total
    other.type_size = type_size
    Platform::POSIX.memcpy other, self, total
    other
  end

  def address= thingy
    Ruby.primitive :memorypointer_set_address
    raise PrimitiveFailure, "Unable to fuck over your address well enough"
  end

  # Indicates how many bytes the chunk of memory that is pointed to takes up.
  attr_accessor :total

  # Indicates how many bytes the type that the pointer is cast as uses.
  attr_accessor :type_size

  # Access the MemoryPointer like a C array, accessing the +which+ number
  # element in memory. The position of the element is calculate from
  # +@type_size+ and +which+. A new MemoryPointer object is returned, which
  # points to the address of the element.
  #
  # Example:
  #   ptr = MemoryPointer.new(:int, 20)
  #   new_ptr = ptr[9]
  #
  # c-equiv:
  #   int *ptr = (int*)malloc(sizeof(int) * 20);
  #   int *new_ptr;
  #   new_ptr = &ptr[9];
  #
  def [](which)
    raise ArgumentError, "unknown type size" unless @type_size
    self + (which * @type_size)
  end

  # Release the memory pointed to back to the OS.
  def free
    self.autorelease = false
    Platform::POSIX.free(self) unless null?
    #self.class.set_address self, nil
  end

  # Write +obj+ as a C int at the memory pointed to.
  def write_int(obj)
    Ruby.primitive :memorypointer_write_int
    raise PrimitiveFailure, "Unable to write integer"
  end

  # Read a C int from the memory pointed to.
  def read_int
    Ruby.primitive :memorypointer_read_int
    raise PrimitiveFailure, "Unable to read integer"
  end

  # Write +obj+ as a C long at the memory pointed to.
  def write_long(obj)
    Ruby.primitive :memorypointer_write_long
    raise PrimitiveFailure, "Unable to write long"
  end

  # Read a C long from the memory pointed to.
  def read_long
    Ruby.primitive :memorypointer_read_long
    raise PrimitiveFailure, "Unable to read long"
  end

  def read_string_length(len)
    Ruby.primitive :memorypointer_read_string
    raise PrimitiveFailure, "Unable to read string"
  end

  def read_string_to_null
    Ruby.primitive :memorypointer_read_string_to_null
    raise PrimitiveFailure, "Unable to read string to null"
  end

  def read_string(len=nil)
    if len
      read_string_length(len)
    else
      read_string_to_null
    end
  end

  def write_string_length(str, len)
    Ruby.primitive :memorypointer_write_string
    raise PrimitiveFailure, "Unable to write string"
  end

  def write_string(str, len=nil)
    len = str.size unless len

    write_string_length(str, len);
  end

  def read_pointer
    Ruby.primitive :memorypointer_read_pointer
    raise PrimitiveFailure, "Unable to read pointer"
  end

  def write_float(obj)
    Ruby.primitive :memorypointer_write_float
    raise PrimitiveFailure, "Unable to write float"
  end

  def read_float
    Ruby.primitive :memorypointer_read_float
    raise PrimitiveFailure, "Unable to read float"
  end

  def read_array_of_int(length)
    read_array_of_type(:int, :read_int, length)
  end

  def write_array_of_int(ary)
    write_array_of_type(:int, :write_int, ary)
  end

  def read_array_of_long(length)
    read_array_of_type(:long, :read_long, length)
  end

  def write_array_of_long(ary)
    write_array_of_type(:long, :write_long, ary)
  end

  def read_array_of_type(type, reader, length)
    ary = []
    size = FFI.type_size(FFI.find_type type)
    tmp = self
    length.times {
      ary << tmp.send(reader)
      tmp += size
    }
    ary
  end

  def write_array_of_type(type, writer, ary)
    size = FFI.type_size(FFI.find_type type)
    tmp = self
    ary.each {|i|
      tmp.send(writer, i)
      tmp += size
    }
    self
  end

  def get_at_offset(offset, type)
    Ruby.primitive :memorypointer_get_at_offset
    raise PrimitiveFailure, "get_field failed"
  end

  def set_at_offset(offset, type, val)
    Ruby.primitive :memorypointer_set_at_offset
    raise PrimitiveFailure, "set_field failed"
  end

  def inspect
    # Don't have this print the data at the location. It can crash everything.
    "#<MemoryPointer address=0x#{address.to_s(16)} size=#{total}>"
  end

  def address
    Ruby.primitive :memorypointer_address
    raise PrimitiveFailure, "Unable to find address"
  end

  def null?
    address == 0x0
  end

  def +(value)
    Ruby.primitive :memorypointer_add
    raise PrimitiveFailure, "Unable to add"
  end

  ##
  # If +val+ is true, this MemoryPointer object will call
  # free() on it's address when it is garbage collected.

  def autorelease=(val)
    Ruby.primitive :memorypointer_set_autorelease
    raise PrimitiveFailure, "Unable to change autorelease"
  end
end

module FFI

  ##
  # Given a +type+ as a number, indicate how many bytes that type
  # takes up on this platform.

  def self.type_size(type)
    Ruby.primitive :nativefunction_type_size
    raise PrimitiveFailure, "Unable to find type size for #{type}"
  end

end

##
# Represents a C struct as ruby class.

class FFI::Struct

  attr_reader :pointer

  def self.layout(*spec)
    return @layout if spec.size == 0

    cspec = LookupTable.new
    i = 0

    @size = 0

    while i < spec.size
      name = spec[i]
      f = spec[i + 1]
      offset = spec[i + 2]

      code = FFI.find_type(f)
      cspec[name] = [offset, code]
      ending = offset + FFI.type_size(code)
      @size = ending if @size < ending

      i += 3
    end

    @layout = cspec unless self == FFI::Struct

    return cspec
  end

  def self.config(base, *fields)
    @size = Rubinius::RUBY_CONFIG["#{base}.sizeof"]
    cspec = LookupTable.new

    fields.each do |field|
      offset = Rubinius::RUBY_CONFIG["#{base}.#{field}.offset"]
      size   = Rubinius::RUBY_CONFIG["#{base}.#{field}.size"]
      type   = Rubinius::RUBY_CONFIG["#{base}.#{field}.type"]
      type   = type ? type.to_sym : FFI.size_to_type(size)

      code = FFI.find_type type
      cspec[field] = [offset, code]
      ending = offset + size
      @size = ending if @size < ending
    end

    @layout = cspec

    return cspec
  end

  def self.size
    @size
  end

  def size
    self.class.size
  end

  def initialize(pointer = nil, *spec)
    @cspec = self.class.layout(*spec)

    if pointer then
      @pointer = pointer
    else
      @pointer = MemoryPointer.new size
    end
  end

  def free
    @pointer.free
  end

  def initialize_copy ptr
    @pointer = @pointer.dup
  end

  def [](field)
    offset, type = @cspec[field]
    raise "Unknown field #{field}" unless offset

    if type == FFI::TYPE_CHARARR
      (@pointer + offset).read_string
    else
      @pointer.get_at_offset(offset, type)
    end
  end

  def []=(field, val)
    offset, type = @cspec[field]
    raise "Unknown field #{field}" unless offset

    @pointer.set_at_offset(offset, type, val)
    return val
  end

end

##
# A C function that can be executed.  Similar to CompiledMethod.

class NativeFunction

  # The *args means the primitive handles it own argument count checks.
  def call(*args)
    Ruby.primitive :nativefunction_call_object
  end

  ##
  # Static C variable like errno.  (May not be used).

  class Variable
    def initialize(library, name, a2, a3=nil)
      if a3
        @ret = a3
        @static_args = a2
      else
        @ret = a2
        @static_args = nil
      end

      @library = library
      @name = name
      @functions = LookupTable.new
    end

    def find_function(at)
      if @static_args
        at = @static_args + at
      end

      if func = @functions[at]
        return func
      end

      func = FFI.create_function @library, @name, at, @ret
      @functions[at] = func
      return func
    end

    def [](*args)
      find_function(args)
    end

    def call(at, *args)
      find_function(at).call(*args)
    end
  end
end

##
# Namespace for holding platform-specific C constants.

module Platform
end

