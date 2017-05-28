require "carrierwave/neo4j/version"
require "neo4j"
require "carrierwave"
require "carrierwave/validations/active_model"
require "carrierwave/neo4j/uploader_converter"
require "active_support/concern"

module CarrierWave
  module Neo4j
    extend ActiveSupport::Concern
    module ClassMethods
      include CarrierWave::Mount
      ##
      # See +CarrierWave::Mount#mount_uploader+ for documentation
      #
      def mount_uploader(column, uploader=nil, options={}, &block)
        super
        class_eval <<-RUBY, __FILE__, __LINE__+1
          def remote_#{column}_url=(url)
            column = _mounter(:#{column}).serialization_column
            send(:attribute_will_change!, :#{column})
            super
          end
        RUBY
      end

      ##
      # See +CarrierWave::Mount#mount_uploaders+ for documentation
      #
      def mount_uploaders(column, uploader=nil, options={}, &block)
        super
        class_eval <<-RUBY, __FILE__, __LINE__+1
          def remote_#{column}_urls=(url)
            column = _mounter(:#{column}).serialization_column
            send(:attribute_will_change!, :#{column})
            super
          end
        RUBY
      end


      private
        def mount_base(column, uploader=nil, options={}, &block)
          super

          serialize column, ::CarrierWave::Uploader::Base

          include CarrierWave::Validations::ActiveModel

          validates_integrity_of  column if uploader_option(column.to_sym, :validate_integrity)
          validates_processing_of column if uploader_option(column.to_sym, :validate_processing)
          validates_download_of column if uploader_option(column.to_sym, :validate_download)

          after_save :"store_#{column}!"
          before_save :"write_#{column}_identifier"

          before_destroy :"clear_#{column}"
          after_destroy :"remove_#{column}!"

          after_save :"store_previous_changes_for_#{column}"
          after_update :"remove_previously_stored_#{column}"

          class_eval <<-RUBY, __FILE__, __LINE__+1

            def #{column}
              _mounter(:#{column}).uploaders[0] ||= _mounter(:#{column}).blank_uploader
              unless #{column}_changed? && read_uploader(:#{column})
                _mounter(:#{column}).uploaders[0].retrieve_from_store!(read_uploader(:#{column}))
               end
              _mounter(:#{column}).uploaders[0]
            end

            def read_uploader(name)
              send(:attribute, name.to_s)
            end

            def write_uploader(name, value)
              send(:attribute=, name.to_s, value)
            end

            def #{column}=(new_file)
              column = _mounter(:#{column}).serialization_column
              if !(new_file.blank? && send(:#{column}).blank?)
                send(:attribute_will_change!, :#{column})
              end

              super
            end

            def clear_#{column}
              write_uploader(_mounter(:#{column}).serialization_column, nil)
            end

            def remove_#{column}=(value)
              column = _mounter(:#{column}).serialization_column
              send(:attribute_will_change!, :#{column})
              super
            end

            def remove_#{column}!
              self.remove_#{column} = true
              write_#{column}_identifier
              self.remove_#{column} = false
              super
            end

            def reload_from_database
              if reloaded = self.class.load_entity(neo_id)
                send(:attributes=, reloaded.attributes.reject{ |k,v| v.is_a?(::CarrierWave::Uploader::Base) })
              end
              reloaded
            end

            def store_previous_changes_for_#{column}
              attribute_changes = changes
              @_previous_changes_for_#{column} = attribute_changes[_mounter(:#{column}).serialization_column]
            end

            def remove_previously_stored_#{column}
              before, after = @_previous_changes_for_#{column}
              _mounter(:#{column}).remove_previous([before], [after])
            end
            # Reset cached mounter on record reload
            def reload(*)
              @_mounters = nil
              super
            end
            # Reset cached mounter on record dup
            def initialize_dup(other)
              @_mounters = nil
              super
            end
          RUBY
        end
      end # ClassMethods
    end # Neo4j
end # CarrierWave

Neo4j::ActiveNode.send :include, CarrierWave::Neo4j
