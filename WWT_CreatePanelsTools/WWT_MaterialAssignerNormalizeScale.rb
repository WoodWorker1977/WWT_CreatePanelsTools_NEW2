require 'sketchup.rb'
require 'json'
require 'set'

module MaterialAssignerNormalizeScale
  VERSION = '2.0.6'
  AUTHOR = 'Ruslan WoodWorkers Tools (ruslan.onopriichuk@gmail.com)'
  
  # Константи
  EPSILON = 1.0e-10
  MAX_RECURSION_DEPTH = 100
  
  @debug_mode = true
  
  class << self
    attr_accessor :debug_mode
    
    # Змінна для контролю стану
    @functionality_enabled = true
    attr_accessor :functionality_enabled

    def functionality_enabled=(value)
      @functionality_enabled = value
      if value
        start_observer
      else
        cleanup_observers
      end
    end

    def functionality_enabled
      if defined?(WWT_CreatePanelsTools)
        WWT_CreatePanelsTools.materials_enabled?
      else
        @functionality_enabled
      end
    end
    
    def start_observer
      cleanup_observers
      @processor ||= MaterialProcessor.new
      
      model = ::Sketchup.active_model
      if model
        @model_observer ||= ModelObserver.new(@processor)
        model.add_observer(@model_observer)
        
        # Додаємо спостерігач тільки до active_entities
        model.active_entities.add_observer(@model_observer)
        
        @tool_observer ||= ToolObserver.new(@processor)
        model.tools.add_observer(@tool_observer)
      end
    end

    def cleanup_observers
      model = ::Sketchup.active_model
      if model
        if defined?(@model_observer) && @model_observer
          model.remove_observer(@model_observer)
          model.active_entities.remove_observer(@model_observer) if model.active_entities
          @model_observer = nil
        end
        if defined?(@tool_observer) && @tool_observer
          model.tools.remove_observer(@tool_observer)
          @tool_observer = nil
        end
      end
    end

    def log(message, level = :info)
      return unless @debug_mode
      prefix = case level
        when :error then "ПОМИЛКА:"
        when :warning then "ПОПЕРЕДЖЕННЯ:"
        else "ІНФО:"
      end
      puts "[MaterialAssignerNormalizeScale] #{prefix} #{message}"
      puts caller.join("\n") if level == :error && @debug_mode
    end

    def get_texture_path(relative_path)
      if defined?(WWT_CreatePanelsTools) && WWT_CreatePanelsTools.respond_to?(:get_texture_path)
        WWT_CreatePanelsTools.get_texture_path(relative_path)
      else
        File.join(::Sketchup.find_support_file("Plugins"), 
                  "WWT_CreatePanelsTools", 
                  "Textures",
                  relative_path)
      end
    end

    def add_observers_to_faces(entities, entity = nil)
      return unless entities && @model_observer
      
      if entity || in_active_path?(entities)
        begin
          entities.add_observer(@model_observer)
          log("Додано спостерігача до entities")
          
          if entity
            if entity.is_a?(::Sketchup::Group) || entity.is_a?(::Sketchup::ComponentInstance)
              definition = entity.is_a?(::Sketchup::Group) ? entity : entity.definition
              if definition && definition.entities
                definition.entities.add_observer(@model_observer)
                log("Додано спостерігача до вкладених entities: #{entity.entityID}")
              end
            end
          end
        rescue => e
          log("Помилка додавання спостерігача: #{e.message}", :error)
        end
      end
    end

    def in_active_path?(entities)
      model = ::Sketchup.active_model
      return false unless model
      
      active_path = model.active_path
      return false unless active_path
      
      active_path.any? do |entity|
        if entity.is_a?(::Sketchup::Group)
          entity.entities == entities
        elsif entity.is_a?(::Sketchup::ComponentInstance) && entity.definition
          entity.definition.entities == entities
        end
      end
    end
  end

  class TransformationState
    attr_reader :entity, :original_transformation

    def initialize(entity)
      @entity = entity
      @original_transformation = entity.transformation.clone
    end

    def restore
      @entity.transformation = @original_transformation if @entity.valid?
    end
  end

  class MaterialProcessor
    def initialize
      @model = ::Sketchup.active_model
      @materials = @model.materials
      @material_settings = {}
      @processing_lock = false
      @processed_faces = Set.new
      
      # Кеші
      @material_cache = {}
      @face_area_cache = {}
      @entity_cache = {}
      @processed_materials = {}
      @entity_transformation_cache = {}
      @priority_queue = []
      @last_processed_time = {}
      @transformation_states = []
      @start_time = nil
      @max_recursion_depth = 10
      @white_material = nil
      
      load_material_settings
    end

    def refresh_materials
      return unless @model && @model.valid?
      @materials = @model.materials
    end

    def needs_processing?
      return false unless MaterialAssignerNormalizeScale.functionality_enabled
      return false unless valid_model?
      return false if @processing_lock
      return false unless @model && @model.entities
      
      depth = @max_recursion_depth || 10
      
      begin
        entities = get_all_nested_groups_and_components(@model.entities, depth)
        return false unless entities
        
        @entity_cache ||= {}
        
        changed_entities = entities.select { |e| entity_changed?(e) }
        
        !changed_entities.empty?
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка в needs_processing?: #{e.message}", :error)
        false
      end
    end

    def process_all_entities
      return unless MaterialAssignerNormalizeScale.functionality_enabled
      return unless valid_model?
      return if @processing_lock
      
      # Отримуємо активний контекст редагування
      active_path = @model.active_path
      
      # Визначаємо колекцію для обробки
      entities_to_process = if active_path && !active_path.empty?
        active_entity = active_path.last
        if active_entity.respond_to?(:definition) && active_entity.definition
          active_entity.definition.entities
        else
          @model.active_entities
        end
      else
        @model.active_entities
      end
      
      # Отримуємо виділені об'єкти в поточному контексті
      selection = @model.selection
      return if selection.empty?
      
      # Фільтруємо тільки ті об'єкти, які належать до поточного контексту
      selected_entities = selection.to_a.select { |entity| 
        entity && entity.valid? && 
        (entity.is_a?(::Sketchup::Group) || entity.is_a?(::Sketchup::ComponentInstance)) &&
        entities_to_process.include?(entity)
      }
      
      return if selected_entities.empty?
      
      @processing_lock = true
      begin
        @model.start_operation('Нормалізувати масштаб і обробити матеріали', true)
        
        selected_entities.each do |entity|
          if should_normalize?(entity)
            normalize_single_entity(entity)
          end
        end
        
        @model.commit_operation
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка обробки об'єктів: #{e.message}", :error)
        @model.abort_operation
      ensure
        @processing_lock = false
        cleanup_processing_state
      end
    end

    def should_normalize?(entity)
      return false unless entity && entity.valid?
      return false if entity.is_a?(::Sketchup::Group) && entity.name == "_ABF_Label"
      
      transformation = entity.transformation
      return false unless valid_transformation?(transformation)
      
      scale = Geom::Vector3d.new(
        transformation.xscale,
        transformation.yscale,
        transformation.zscale
      )
      
      x_diff = (scale.x - 1.0).abs
      y_diff = (scale.y - 1.0).abs
      z_diff = (scale.z - 1.0).abs
      
      x_diff > EPSILON || y_diff > EPSILON || z_diff > EPSILON
    end

    def normalize_single_entity(entity)
      return unless entity && entity.valid?
      return if entity.is_a?(::Sketchup::Group) && entity.name == "_ABF_Label"
      
      initial_transformation = entity.transformation
      return unless valid_transformation?(initial_transformation)
      
      MaterialAssignerNormalizeScale.log("Обробка масштабування об'єкта: #{entity.entityID}")
      
      begin
        return unless @model && @model.valid?
        return unless @materials && @materials.valid?
        
        if entity.is_a?(::Sketchup::Group) && entity.definition.instances.length > 1
          MaterialAssignerNormalizeScale.log("Робимо групу унікальною: #{entity.entityID}")
          entity.make_unique
        end
        
        original_material = entity.material
        
        scale, rotation, inversion = decompose_transformation(initial_transformation)
        
        new_transformation = combine_transformation(rotation, initial_transformation.origin, inversion)
        entity.transformation = new_transformation
        
        entities = nil
        if entity.is_a?(::Sketchup::Group)
          entities = entity.entities
        elsif entity.is_a?(::Sketchup::ComponentInstance)
          entities = entity.definition.entities
        end
        
        if entities
          scale_compensation = Geom::Transformation.scaling(
            scale.x.abs,
            scale.y.abs,
            scale.z.abs
          )
          
          entities.transform_entities(scale_compensation, entities.to_a)
        end
        
        if entity.material != original_material && original_material
          entity.material = original_material
        end
        
        if entity.valid? && entity.material
          process_materials(entity)
          process_small_faces_manually(entity)
        end
        
        MaterialAssignerNormalizeScale.log("Нормалізацію об'єкта #{entity.entityID} завершено")
        
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка в normalize_single_entity: #{e.message}", :error)
        raise
      end
    end

    def process_small_faces_manually(entity)
      return unless entity && entity.valid?
      return unless entity.material
      
      all_faces = []
      if entity.is_a?(::Sketchup::Group) && entity.entities
        all_faces = entity.entities.grep(::Sketchup::Face)
      elsif entity.is_a?(::Sketchup::ComponentInstance) && entity.definition && entity.definition.entities
        all_faces = entity.definition.entities.grep(::Sketchup::Face)
      end
      
      return if all_faces.empty?
      
      sorted_faces = all_faces.select(&:valid?).sort_by { |f| f.area }.reverse
      
      two_largest = sorted_faces.take(2)
      small_faces = sorted_faces.drop(2)
      
      material_data = nil
      if respond_to?(:find_material_in_settings)
        material_data = find_material_in_settings(entity.material.name)
      end
      
      small_faces.each do |face|
        next unless face.valid?
        
        abf_dict = face.attribute_dictionary('ABF', false)
        if abf_dict && abf_dict['edge-band-id']
          face.material = entity.material
        elsif material_data
          edge_material = nil
          if respond_to?(:get_edge_material)
            edge_material = get_edge_material(material_data)
          end
          
          if edge_material
            face.material = edge_material
          else
            face.material = entity.material
          end
        else
          face.material = entity.material
        end
      end
    end
    
        def process_materials(entity)
      return unless MaterialAssignerNormalizeScale.functionality_enabled
      return if @processing_lock
      return unless entity.valid? && entity.material
      
      cache_key = "#{entity.entityID}_#{entity.material.name}"
      return if @processed_materials[cache_key] && 
               Time.now - @processed_materials[cache_key] < 1.0
      
      @processing_lock = true
      begin
        material_data = find_material_in_settings(entity.material.name)
        return unless material_data
    
        wwt_dict = entity.attribute_dictionary('WWT', true)
        update_entity_attributes(entity, wwt_dict, material_data)
        process_entity_faces(entity, material_data)
        
        @processed_materials[cache_key] = Time.now
      ensure
        @processing_lock = false
      end
    end

    def process_entity_faces(entity, material_data)
      faces = entity.definition.entities.grep(::Sketchup::Face)
      return if faces.empty?
    
      sorted_faces = faces.sort_by do |face|
        cache_key = "area_#{face.entityID}"
        @face_area_cache[cache_key] ||= face.area
      end.reverse
      
      two_largest_faces = sorted_faces.take(2)
      
      is_material_from_json = material_data != nil
      edge_material = is_material_from_json ? get_edge_material(material_data) : nil
      entity_material = entity.material
      
      model = ::Sketchup.active_model
      white_material = ensure_white_material(model)
    
      is_single_sided = is_material_from_json && 
                       material_data['sidedness'] && 
                       material_data['sidedness']['type'] == 'Single_sided'
    
      faces.each do |face|
        next unless face.valid? && !face.deleted?
        
        if two_largest_faces.include?(face)
          process_large_face(face, is_single_sided, white_material)
        else
          process_edge_face(face, entity, edge_material, entity_material, is_material_from_json)
        end
      end
    end

    def process_large_face(face, is_single_sided, white_material)
      return unless face.valid?
      
      if is_single_sided
        face.material = white_material 
        face.set_attribute("WWT", "sidedness_type", "Single_sided")
      else
        face.material = nil
        face.delete_attribute("WWT", "sidedness_type")
      end
    end
    
    def process_edge_face(face, entity, edge_material, entity_material, is_material_from_json)
      abf_dict = face.attribute_dictionary('ABF', false)
      
      if abf_dict && abf_dict['edge-band-id']
        face.material = entity_material if entity_material
      else
        if is_material_from_json && edge_material
          face.material = edge_material
        else
          face.material = entity_material if entity_material
        end
      end
    end

    def ensure_white_material(model)
      return @white_material if @white_material && @white_material.valid?
      
      @white_material = model.materials["Material"]
      unless @white_material
        @white_material = model.materials.add("Material")
        @white_material.color = ::Sketchup::Color.new(255, 255, 255)
      end
      @white_material
    end

    def get_edge_material(material_data)
      return nil unless material_data && @materials && @materials.valid?
      
      material_name = material_data['name']
      cache_key = "edge_#{material_name}"
      
      return @material_cache[cache_key] if @material_cache[cache_key]
      
      edge_material = @materials[material_name]
      
      unless edge_material
        MaterialAssignerNormalizeScale.log("Створення нового матеріалу: #{material_name}")
        edge_material = @materials.add(material_name)
        edge_material.color = ::Sketchup::Color.new(255, 255, 255)
        apply_edge_material_properties(edge_material, material_data)
      end
      
      @material_cache[cache_key] = edge_material
      edge_material
    end

    def apply_edge_material_properties(material, material_data)
      begin
        case material_data['material_type']
        when 'texture'
          if path = material_data.dig('texture_paths', 'main')
            if texture_path = MaterialAssignerNormalizeScale.get_texture_path(path)
              if File.exist?(texture_path)
                material.color = ::Sketchup::Color.new(255, 255, 255)
                
                @model.start_operation('Apply Material Texture', true)
                material.texture = texture_path
                @model.commit_operation
              else
                material.color = ::Sketchup::Color.new(200, 200, 200)
              end
            end
          end
        when 'color'
          if color_props = material_data.dig('color_properties', 'main')
            if color_props['color'].is_a?(Array) && color_props['color'].size >= 3
              material.color = ::Sketchup::Color.new(*color_props['color'])
              material.alpha = color_props['alpha'] if color_props['alpha']
            end
          end
        end
      rescue => e
        MaterialAssignerNormalizeScale.log("Помилка при застосуванні властивостей матеріалу: #{e.message}", :error)
        material.color = ::Sketchup::Color.new(200, 200, 200)
      end
    end

    def entity_changed?(entity)
      return false unless entity && entity.valid?
      
      begin
        @entity_cache ||= {}
        
        cache_key = "#{entity.entityID}_#{entity.transformation.hash}"
        current_material = entity.material&.name || 'no_material'
        
        changed = @entity_cache[cache_key] != current_material
        
        @entity_cache[cache_key] = current_material
        
        changed
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка при перевірці змін в об'єкті: #{e.message}", :error)
        false
      end
    end

    def get_all_nested_groups_and_components(entities, max_depth = 10)
      result = []
      
      return result if max_depth.nil? || max_depth <= 0 
      return result if !entities || !entities.respond_to?(:find_all)
      
      begin
        groups_and_components = entities.find_all { |e| 
          e && e.valid? && (e.is_a?(::Sketchup::Group) || e.is_a?(::Sketchup::ComponentInstance))
        }
        
        result.concat(groups_and_components)
        
        groups_and_components.each do |entity|
          next unless entity && entity.valid?
          
          if entity.respond_to?(:definition) && entity.definition && entity.definition.valid? && 
             entity.definition.entities && entity.definition.entities.respond_to?(:find_all)
            nested = get_all_nested_groups_and_components(
              entity.definition.entities, 
              max_depth - 1
            )
            result.concat(nested) unless nested.nil? || nested.empty?
          end
        end
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка в get_all_nested_groups_and_components: #{e.message}", :error)
      end
      
      result
    end

    def valid_transformation?(transformation)
      return false unless transformation.is_a?(Geom::Transformation)
      
      matrix = transformation.to_a
      return false if matrix.any? { |v| v.nil? || v.nan? || v.infinite? }
      
      determinant = matrix[0] * (matrix[5] * matrix[10] - matrix[6] * matrix[9]) -
                   matrix[1] * (matrix[4] * matrix[10] - matrix[6] * matrix[8]) +
                   matrix[2] * (matrix[4] * matrix[9] - matrix[5] * matrix[8])
      
      determinant.abs > EPSILON
    end

    def decompose_transformation(transformation)
      scale = Geom::Vector3d.new(
        transformation.xscale,
        transformation.yscale,
        transformation.zscale
      )
      
      rotation = extract_rotation(transformation)
      inversion = scale.x < 0 || scale.y < 0 || scale.z < 0
      
      [scale, rotation, inversion]
    end
    
        def extract_rotation(transformation)
      x_axis = transformation.xaxis.normalize
      y_axis = transformation.yaxis.normalize
      z_axis = transformation.zaxis.normalize
      
      Geom::Transformation.axes(
        Geom::Point3d.new(0, 0, 0),
        x_axis,
        y_axis,
        z_axis
      )
    end

    def combine_transformation(rotation, origin, inversion)
      unity_scale = Geom::Transformation.scaling(1, 1, 1)
      translation = Geom::Transformation.translation(origin)
      inversion_transform = inversion ? Geom::Transformation.scaling(-1, -1, -1) : Geom::Transformation.new
      
      translation * rotation * unity_scale * inversion_transform
    end

    def cleanup_processing_state
      @transformation_states.clear if @transformation_states
      @start_time = nil
      @face_area_cache.clear if @face_area_cache
      @processed_materials.clear if @processed_materials
    end

    def find_parent_container(entity)
      return nil unless entity && entity.valid?
      
      model = ::Sketchup.active_model
      active_path = model.active_path
      
      if active_path && !active_path.empty?
        active_entity = active_path.last
        if active_entity.is_a?(::Sketchup::Group) || active_entity.is_a?(::Sketchup::ComponentInstance)
          return active_entity
        end
      end
      
      if entity.respond_to?(:parent_entities) && entity.parent_entities
        parent_entities = entity.parent_entities
        if parent_entities.respond_to?(:parent) && parent_entities.parent
          parent = parent_entities.parent
          if parent.is_a?(::Sketchup::Group) || parent.is_a?(::Sketchup::ComponentInstance)
            return parent
          elsif parent.is_a?(::Sketchup::ComponentDefinition)
            instances = parent.instances
            if instances && !instances.empty?
              return instances[0]
            end
          end
        end
      end
      
      parent = entity
      
      while parent.respond_to?(:parent) && parent.parent
        parent = parent.parent
        
        if parent.is_a?(::Sketchup::Group) || parent.is_a?(::Sketchup::ComponentInstance)
          return parent
        end
        
        if parent.is_a?(::Sketchup::ComponentDefinition)
          instances = parent.instances
          if instances && !instances.empty?
            return instances[0]
          end
        end
      end
      
      nil
    end

    def load_material_settings
      begin
        file_path = File.join(::Sketchup.find_support_file("Plugins"), 
                           "WWT_CreatePanelsTools", 
                           "settings", 
                           "panel_defaults.json")
        return unless File.exist?(file_path)
        json_data = File.read(file_path)
        @material_settings = JSON.parse(json_data)["materials"]
        MaterialAssignerNormalizeScale.log("Налаштування матеріалів завантажено успішно")
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка завантаження налаштувань матеріалів: #{e.message}", :error)
        @material_settings = {}
      end
    end

    def valid_model?
      @model && @model.valid?
    end

    def normalize_material_name(name)
      return "" unless name
      name.gsub(/[*_]/, '').strip.downcase
    end

    def material_names_match?(normalized_input, material_data)
      normalized_name = normalize_material_name(material_data['name'])
      normalized_display = material_data['display_name'] ? 
        normalize_material_name(material_data['display_name']) : nil
      
      normalized_input == normalized_name || 
        normalized_input == normalized_display ||
        (normalized_input.include?('ldsp') && 
         normalized_name.include?('ldsp') && 
         normalized_input.start_with?(normalized_name))
    end

    def find_material_in_settings(material_name)
      return nil unless material_name
      normalized_name = normalize_material_name(material_name)
      
      @material_settings.each do |id, data|
        if material_names_match?(normalized_name, data)
          return data.merge('id' => id)
        end
      end
      nil
    end

    def update_entity_attributes(entity, wwt_dict, material_data)
      wwt_dict['ID_panels'] = material_data['id']
      wwt_dict['material_name'] = material_data['name']
      wwt_dict['material_type'] = material_data['material_type']
      
      update_entity_layer(entity, material_data)
    end

    def update_entity_layer(entity, material_data)
      return unless entity.valid?
      
      layer_name = material_data['layer_name']
      return unless layer_name

      model = ::Sketchup.active_model
      layer = model.layers[layer_name] || model.layers.add(layer_name)
      
      entity.layer = layer
      
      wwt_dict = entity.attribute_dictionary('WWT', true)
      wwt_dict['layer'] = layer_name if wwt_dict
    end
  end # кінець класу MaterialProcessor
  
    class ModelObserver < ::Sketchup::ModelObserver
    def initialize(processor)
      @processor = processor
      @processing_lock = false
    end

    def onTransactionCommit(model)
      return if @processing_lock
      
      begin
        @processing_lock = true
        
        if @processor
          @processor.refresh_materials if @processor.respond_to?(:refresh_materials)
          
          selection = model.selection
          if !selection.empty?
            scaled_entities = selection.to_a.select { |entity| 
              entity && entity.valid? && 
              (entity.is_a?(::Sketchup::Group) || entity.is_a?(::Sketchup::ComponentInstance)) &&
              @processor.respond_to?(:should_normalize?) && @processor.should_normalize?(entity)
            }
            
            if !scaled_entities.empty?
              @processor.process_all_entities if @processor.respond_to?(:process_all_entities)
            end
          end
        end
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка при обробці транзакції: #{e.message}", :error)
      ensure
        @processing_lock = false
      end
    end

    def onActivePathChanged(model)
      return if @processing_lock
      
      begin
        @processing_lock = true
        
        active_path = model.active_path
        
        if active_path && !active_path.empty?
          active_entity = active_path.last
          
          if active_entity.is_a?(::Sketchup::Group) || active_entity.is_a?(::Sketchup::ComponentInstance)
            entities = active_entity.is_a?(::Sketchup::Group) ? 
                      active_entity.entities : 
                      (active_entity.definition ? active_entity.definition.entities : nil)
            
            if entities
              MaterialAssignerNormalizeScale.add_observers_to_faces(entities, active_entity)
            end
          end
        end
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка при зміні активного шляху: #{e.message}", :error)
      ensure
        @processing_lock = false
      end
    end

    def onElementAdded(entities, entity)
      return if @processing_lock
      
      begin
        @processing_lock = true
        
        if MaterialAssignerNormalizeScale.in_active_path?(entities)
          if entity.is_a?(::Sketchup::Group) || entity.is_a?(::Sketchup::ComponentInstance)
            MaterialAssignerNormalizeScale.add_observers_to_faces(entities, entity)
          elsif entity.is_a?(::Sketchup::Face)
            process_face_with_parent_material(entity)
          end
        end
      ensure
        @processing_lock = false
      end
    end

    def onElementModified(entities, entity)
      return if @processing_lock
      return unless entity.is_a?(::Sketchup::Face)
      
      begin
        @processing_lock = true
        
        if MaterialAssignerNormalizeScale.in_active_path?(entities)
          ::UI.start_timer(0.1) {
            begin
              if entity && entity.valid?
                process_face_with_parent_material(entity)
              end
            rescue StandardError => e
              MaterialAssignerNormalizeScale.log("Помилка при обробці модифікованої грані: #{e.message}", :error)
            ensure
              @processing_lock = false
            end
          }
        end
      ensure
        @processing_lock = false
      end
    end

    private

    def process_face_with_parent_material(face)
      return unless face && face.valid?
      
      parent = find_parent_container(face)
      return unless parent && parent.valid? && parent.material
      return if parent.is_a?(::Sketchup::Group) && parent.name == "_ABF_Label"
      
      begin
        ::Sketchup.active_model.start_operation('Застосувати матеріал до грані', true)
        
        all_faces = []
        if parent.is_a?(::Sketchup::Group) && parent.entities
          all_faces = parent.entities.grep(::Sketchup::Face)
        elsif parent.is_a?(::Sketchup::ComponentInstance) && parent.definition && parent.definition.entities
          all_faces = parent.definition.entities.grep(::Sketchup::Face)
        end
        
        if all_faces.size > 0
          sorted_faces = all_faces.select(&:valid?).sort_by { |f| f.area }.reverse
          two_largest = sorted_faces.take(2)
          
          if !two_largest.include?(face)
            material_data = nil
            if @processor && @processor.respond_to?(:find_material_in_settings)
              material_data = @processor.find_material_in_settings(parent.material.name)
            end
            
            if material_data
              abf_dict = face.attribute_dictionary('ABF', false)
              if abf_dict && abf_dict['edge-band-id']
                face.material = parent.material
              else
                edge_material = nil
                if @processor && @processor.respond_to?(:get_edge_material)
                  edge_material = @processor.get_edge_material(material_data)
                end
                
                if edge_material
                  face.material = edge_material
                else
                  face.material = parent.material
                end
              end
            else
              face.material = parent.material
            end
          else
            material_data = nil
            if @processor && @processor.respond_to?(:find_material_in_settings)
              material_data = @processor.find_material_in_settings(parent.material.name)
            end
            
            if material_data && material_data['sidedness'] && 
               material_data['sidedness']['type'] == 'Single_sided'
              white_material = nil
              if @processor && @processor.respond_to?(:ensure_white_material)
                white_material = @processor.ensure_white_material(::Sketchup.active_model)
              end
              
              if white_material
                face.material = white_material
              end
            end
          end
        end

        face.layer = parent.layer if parent.layer
        
        ::Sketchup.active_model.commit_operation
      rescue StandardError => e
        MaterialAssignerNormalizeScale.log("Помилка обробки грані: #{e.message}", :error)
        ::Sketchup.active_model.abort_operation
      end
    end

    def find_parent_container(entity)
      return nil unless entity && entity.valid?
      
      model = ::Sketchup.active_model
      active_path = model.active_path
      
      if active_path && !active_path.empty?
        active_entity = active_path.last
        if active_entity.is_a?(::Sketchup::Group) || active_entity.is_a?(::Sketchup::ComponentInstance)
          return active_entity
        end
      end

      if entity.respond_to?(:parent_entities) && entity.parent_entities
        parent_entities = entity.parent_entities
        if parent_entities.respond_to?(:parent) && parent_entities.parent
          parent = parent_entities.parent
          if parent.is_a?(::Sketchup::Group) || parent.is_a?(::Sketchup::ComponentInstance)
            return parent
          elsif parent.is_a?(::Sketchup::ComponentDefinition)
            instances = parent.instances
            if instances && !instances.empty?
              return instances[0]
            end
          end
        end
      end
      
      parent = entity
      
      while parent.respond_to?(:parent) && parent.parent
        parent = parent.parent
        
        if parent.is_a?(::Sketchup::Group) || parent.is_a?(::Sketchup::ComponentInstance)
          return parent
        end
        
        if parent.is_a?(::Sketchup::ComponentDefinition)
          instances = parent.instances
          if instances && !instances.empty?
            return instances[0]
          end
        end
      end
      
      nil
    end
  end # кінець класу ModelObserver

  class ToolObserver < ::Sketchup::ToolsObserver
    def initialize(processor)
      @processor = processor
    end

    def onActiveToolChanged(tools, tool_name, tool_id)
      if tool_name == "ScaleTool" || tool_id == 21017
        MaterialAssignerNormalizeScale.log("Активовано інструмент масштабування")
        ::UI.start_timer(0.1) { 
          begin
            if @processor
              @processor.process_all_entities
            end
          rescue StandardError => e
            MaterialAssignerNormalizeScale.log("Помилка в onActiveToolChanged: #{e.message}", :error)
          end
        }
      end
    end
  end

  class AppObserver < ::Sketchup::AppObserver
    def onNewModel(model)
      MaterialAssignerNormalizeScale.start_observer
    end
    
    def onOpenModel(model)
      MaterialAssignerNormalizeScale.start_observer
    end
  end

  class OperationTimeoutError < StandardError; end

  def self.load_extension
    unless @loaded
      @loaded = true
      ::Sketchup.add_observer(AppObserver.new)
      
      ::UI.start_timer(1.0) {
        start_observer
        MaterialAssignerNormalizeScale.log("Розширення ініціалізовано із затримкою")
      }
    end
  end

  # Initialize the plugin
  unless file_loaded?(__FILE__)
    MaterialAssignerNormalizeScale.load_extension
    file_loaded(__FILE__)
  end
end # кінець модуля MaterialAssignerNormalizeScale
