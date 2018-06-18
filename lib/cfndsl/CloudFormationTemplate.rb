require 'cfndsl/JSONable'
require 'cfndsl/names'

module CfnDsl
  class CloudFormationTemplate < JSONable
    ##
    # Handles the overall template object
    dsl_attr_setter :AWSTemplateFormatVersion, :Description, :Transform
    dsl_content_object :Condition, :Parameter, :Output, :Resource, :Mapping
    attr_accessor :Resources, :Parameters, :Outputs

    def initialize
      @AWSTemplateFormatVersion = '2010-09-09'
      @Transform = 'AWS::Serverless-2016-10-31'
    end

    @@globalRefs = {
      'AWS::NotificationARNs' => 1,
      'AWS::Region' => 1,
      'AWS::StackId' => 1,
      'AWS::StackName' => 1,
      'AWS::AccountId' => 1,
      'AWS::NoValue' => 1
    }

    def isValidRef(ref, origin = nil)
      ref = ref.to_s
      origin = origin.to_s if origin

      return true if @@globalRefs.key?(ref)

      return true if @Parameters && @Parameters.key?(ref)

      if @Resources.key?(ref)
        return !origin || !@_ResourceRefs || !@_ResourceRefs[ref] || !@_ResourceRefs[ref].key?(origin)
      end

      false
    end

    def checkRefs
      invalids = []
      @_ResourceRefs = {}
      if @Resources
        @Resources.keys.each do |resource|
          @_ResourceRefs[resource.to_s] = @Resources[resource].references({})
        end
        @_ResourceRefs.keys.each do |origin|
          @_ResourceRefs[origin].keys.each do |ref|
            invalids.push "Invalid Reference: Resource #{origin} refers to #{ref}" unless isValidRef(ref, origin)
          end
        end
      end
      outputRefs = {}
      if @Outputs
        @Outputs.keys.each do |resource|
          outputRefs[resource.to_s] = @Outputs[resource].references({})
        end
        outputRefs.keys.each do |origin|
          outputRefs[origin].keys.each do |ref|
            invalids.push "Invalid Reference: Output #{origin} refers to #{ref}" unless isValidRef(ref, nil)
          end
        end
      end
      !invalids.empty? ? invalids : nil
    end

    names = {}
    nametypes = {}
    CfnDsl::Types::AWS_Types['Resources'].each_pair do |name, type|
      # Subclass ResourceDefinition and generate property methods
      klass = Class.new(CfnDsl::ResourceDefinition)
      klassname = name.split('::').join('_')
      CfnDsl::Types.const_set(klassname, klass)

      klass.instance_eval do
        define_method(:initialize) do |*_values|
          @Type = name
        end
      end

      type['Properties'].each_pair do |pname, ptype|
        if ptype.instance_of? String
          create_klass = CfnDsl::Types.const_get(ptype)

          klass.class_eval do
            CfnDsl.methodNames(pname) do |method|
              define_method(method) do |*values, &block|
                values.push create_klass.new if values.empty?
                @Properties ||= {}
                @Properties[pname] ||= CfnDsl::PropertyDefinition.new(*values)
                @Properties[pname].value.instance_eval &block if block
                @Properties[pname].value
              end
            end
          end
        else
          # Array version
          sing_name = CfnDsl::Plurals.singularize(pname)
          create_klass = CfnDsl::Types.const_get(ptype[0])
          klass.class_eval do
            CfnDsl.methodNames(pname) do |method|
              define_method(method) do |*values, &block|
                values.push [] if values.empty?
                @Properties ||= {}
                @Properties[pname] ||= PropertyDefinition.new(*values)
                @Properties[pname].value.instance_eval &block if block
                @Properties[pname].value
              end
            end

            CfnDsl.methodNames(sing_name) do |method|
              define_method(method) do |value = nil, &block|
                @Properties ||= {}
                @Properties[pname] ||= PropertyDefinition.new([])
                value ||= create_klass.new
                @Properties[pname].value.push value
                value.instance_eval &block if block
                value
              end
            end
          end
        end
      end
      parts = name.split '::'
      until parts.empty?
        abreve_name = parts.join '_'
        if names.key? abreve_name
          # this only happens if there is an ambiguity
          names[abreve_name] = nil
        else
          names[abreve_name] = CfnDsl::Types.const_get(klassname)
          CfnDsl::Types.const_set(abreve_name, klass) unless klassname == abreve_name
          nametypes[abreve_name] = name
        end
        parts.shift
      end
    end

    # Define property setter methods for each of the unambiguous type names
    names.each_pair do |typename, type|
      next unless type
      class_eval do
        CfnDsl.methodNames(typename) do |method|
          define_method(method) do |name, *values, &block|
            name = name.to_s
            @Resources ||= {}
            resource = @Resources[name] ||= type.new(*values)
            resource.instance_eval &block if block
            resource.instance_variable_set('@Type', nametypes[typename])
            resource
          end
        end
      end
    end
  end
end
