require 'sketchup.rb'

module WWT_CreatePanelsTools
  module WWT_CreateSinglePanel

    class CreateSinglePanel
    ORIGIN = Geom::Point3d.new(0, 0, 0)
    
      unless defined?(self::SETTINGS_KEY)
        SETTINGS_KEY = "CreateSinglePanel_Settings"
        UP_KEY = 38
        LEFT_KEY = 37
        RIGHT_KEY = 39
        DOWN_KEY = 40
        CONSTRAIN_MODIFIER_KEY = 16 # ShiftKey
        COPY_MODIFIER_KEY = 17      # ControlKey
        ALT_MODIFIER_KEY = 18       # AltKey
        TAB_KEY = 9
        ESC_KEY = 27
        SPACE_KEY = 32
      end

def initialize
  @version = "V.8"
  @developer_contact = "WoodWorkersTools"

  # Спочатку завантажуємо налаштування
  settings = initialize_default_settings
  # Додаємо відстеження контексту редагування
  @edit_transform = nil
  update_edit_transform
  
  if settings
    @materials_settings = settings["materials"] || {}
    @current_settings = settings["last_used_settings"] || {}
    current_material = settings["current_material"]
    
    if current_material && @materials_settings[current_material]
      material = @materials_settings[current_material]
      
      @panel_material_type = current_material
      @object_z = material["object_z"].to_f.mm
      @object_name = material["object_names"]&.first || "Панель"
      @layer_name = material["layer_name"]
      @gaps = material["gaps"] || [0, 0, 0, 0]
      @left_gap = @gaps[0].to_f.mm
      @right_gap = @gaps[1].to_f.mm
      @top_gap = @gaps[2].to_f.mm
      @bottom_gap = @gaps[3].to_f.mm
      @has_edge = material["has_edge"].nil? ? true : material["has_edge"]
    end
  else
    # Встановлюємо значення за замовчуванням, якщо налаштування не завантажились
    @materials_settings = {}
    @current_settings = {}
    @panel_material_type = nil
    @object_z = 18.mm
    @object_name = "Панель"
    @layer_name = "Default"
    @gaps = [0, 0, 0, 0]
    @left_gap = 0.mm
    @right_gap = 0.mm
    @top_gap = 0.mm
    @bottom_gap = 0.mm
    @has_edge = true
  end

  # Решта ініціалізації
  @ip = Sketchup::InputPoint.new
  @state = 0
  @drawing_plane = :XY
  @last_created_entity = nil
  @shift_pressed = false
  @ctrl_pressed = false
  @alt_pressed = false
  @tab_pressed = false
  @keyboard_input = false
  @fixed_direction = nil
  @drop_state = 0
  @user_width = 0
  @user_height = 0
  @show_panel_material = true
  @state_object = @current_settings["state_object"] || 0
end

def load_textures_if_needed
  return if @textures_loaded
  
  begin
    textures_dir = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "Texturs")
    FileUtils.mkdir_p(textures_dir) unless Dir.exist?(textures_dir)
    
    # Ініціалізація текстур з налаштувань
    initialize_texture_paths
    validate_textures
    
    @textures_loaded = true
  rescue StandardError => e
#    puts "Помилка при завантаженні текстур: #{e.message}"
  end
end

def validate_textures
  return if @textures_validated
  return unless @panel_material_type 

  textures_dir = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "Texturs")
  missing_textures = []

  material = @materials_settings[@panel_material_type]
  if material && material["texture_paths"]
    main_texture = material["texture_paths"]["main"]
    edge_texture = material["texture_paths"]["edge"]

    # Перевірка, чи шлях до текстури є відносним
    main_path = File.absolute_path(main_texture).start_with?(textures_dir) ? main_texture : File.join(textures_dir, main_texture)
    edge_path = File.absolute_path(edge_texture).start_with?(textures_dir) ? edge_texture : File.join(textures_dir, edge_texture)

    missing_textures << "Основна текстура не знайдена для #{material['name']}: #{main_path}" unless File.exist?(main_path)
    missing_textures << "Текстура краю не знайдена для #{material['name']}: #{edge_path}" unless File.exist?(edge_path)
  end

  if missing_textures.any?
    missing_textures.each { |msg| puts msg }
  else
#    puts "Усі текстури успішно знайдено для матеріалу #{@panel_material_type}."
  end

  @textures_validated = true
end

def create_material_from_settings(model, material_type)
  return [nil, nil] unless model && material_type
  
  material_settings = @materials_settings[material_type]
  unless material_settings
    puts "Не знайдено налаштування для матеріалу типу: #{material_type}"
    return [nil, nil]
  end
  
  main_material = nil
  edge_material = nil
  
  begin
    case material_settings["material_type"]
    when "texture"
      if material_settings["texture_paths"]
        # Основний матеріал
        main_material_name = "_#{material_settings['name']}"
        main_material = model.materials[main_material_name] || model.materials.add(main_material_name)
        
        if material_settings["texture_paths"]["main"]
          main_texture_path = get_texture_path(material_settings["texture_paths"]["main"])
          if main_texture_path && File.exist?(main_texture_path)
            begin
              main_material.texture = main_texture_path
              puts "Застосовано основну текстуру: #{main_texture_path}"
            rescue => e
              puts "Помилка застосування основної текстури: #{e.message}"
            end
          else
            puts "Не знайдено основну текстуру: #{material_settings["texture_paths"]["main"]}"
          end
        end
        
        # Матеріал для граней
        edge_material_name = material_settings['name'].to_s
        edge_material = model.materials[edge_material_name] || model.materials.add(edge_material_name)
        
        if material_settings["texture_paths"]["edge"]
          edge_texture_path = get_texture_path(material_settings["texture_paths"]["edge"])
          if edge_texture_path && File.exist?(edge_texture_path)
            begin
              edge_material.texture = edge_texture_path
              puts "Застосовано текстуру краю: #{edge_texture_path}"
            rescue => e
              puts "Помилка застосування текстури краю: #{e.message}"
            end
          else
            puts "Не знайдено текстуру краю: #{material_settings["texture_paths"]["edge"]}"
          end
        end
      end
      
    when "color"
      if material_settings["color_properties"]
        # Основний матеріал
        main_material_name = "_#{material_settings['name']}"
        main_material = model.materials[main_material_name] || model.materials.add(main_material_name)
        
        if material_settings["color_properties"]["main"]
          main_props = material_settings["color_properties"]["main"]
          if main_props["color"].is_a?(Array) && main_props["color"].size >= 3
            main_material.color = Sketchup::Color.new(*main_props["color"])
            main_material.alpha = main_props["alpha"] if main_props["alpha"]
          end
        end
        
        # Матеріал для граней
        edge_material_name = material_settings['name'].to_s
        edge_material = model.materials[edge_material_name] || model.materials.add(edge_material_name)
        
        if material_settings["color_properties"]["edge"]
          edge_props = material_settings["color_properties"]["edge"]
          if edge_props["color"].is_a?(Array) && edge_props["color"].size >= 3
            edge_material.color = Sketchup::Color.new(*edge_props["color"])
            edge_material.alpha = edge_props["alpha"] if edge_props["alpha"]
          end
        end
      end
    end
    
    # Додаємо атрибути до матеріалів
    [main_material, edge_material].each do |material|
      if material
        material.attribute_dictionary("WWT", true)
        material.set_attribute("WWT", "material_type", material_settings["material_type"])
        material.set_attribute("WWT", "material_name", material_settings["name"])
      end
    end
    
  rescue => e
    puts "Помилка при створенні матеріалу: #{e.message}"
    puts "Тип матеріалу: #{material_type}"
    puts "Налаштування: #{material_settings.inspect}"
    puts e.backtrace
  end
  
  [main_material, edge_material]
end

def create_materials
  model = Sketchup.active_model
  materials = model.materials
  
  # Базова назва матеріалу
  base_name = "Material"
  material_name = base_name
  
  # Якщо матеріал вже існує, повертаємо його
  return materials[material_name] if materials[material_name]
  
  # Створюємо новий матеріал
  white_material = materials.add(material_name)
  white_material.color = Sketchup::Color.new(255, 255, 255)
  
  white_material
end

def get_or_create_material_for_id(id_panels)
  model = Sketchup.active_model
  materials = model.materials
  
  # Спочатку шукаємо існуючий матеріал з відповідним ID
  existing_material = materials.to_a.find do |mat|
    dict = mat.attribute_dictionary("WWT")
    dict && dict["ID_panels"] == id_panels
  end
  
  return existing_material if existing_material
  
  # Якщо не знайдено, створюємо новий
  base_name = "Material"
  material_name = base_name
  
  # Додаємо суфікс, якщо ім'я вже зайняте
  counter = 1
  while materials[material_name]
    material_name = "#{base_name}_#{counter}"
    counter += 1
  end
  
  new_material = materials.add(material_name)
  new_material.color = Sketchup::Color.new(255, 255, 255)
  
  # Додаємо атрибут ID_panels
  new_material.attribute_dictionary("WWT", true)
  new_material.set_attribute("WWT", "ID_panels", id_panels)
  
  new_material
end

# Допоміжні методи для створення специфічних матеріалів
def create_mdf_painted(model)
  create_material_from_settings(model, "MDF painted")
end

def create_glass_materials(model)
  create_material_from_settings(model, "Glass")
end

def initialize_texture_paths
  textures_dir = File.join(File.dirname(__FILE__), "Texturs")
  @texture_paths = {}
  
  @materials_settings.each do |id, material|
    next unless material["material_type"] == "texture" && material["texture_paths"]
    
    main_texture = material["texture_paths"]["main"]
    edge_texture = material["texture_paths"]["edge"]
    
    # Використовуємо тільки імена файлів, а не повні шляхи
    @texture_paths[id] = {
      main: File.join(textures_dir, File.basename(main_texture)),
      edge: File.join(textures_dir, File.basename(edge_texture))
    }
  end
end

def activate
  model = Sketchup.active_model
  selection = model.selection
  selection.clear
  make_groups_unique

  @state = 0
  @start_point = nil
  @end_point = nil
  @keyboard_input = false
  @user_width = 0
  @user_height = 0
  @ip = Sketchup::InputPoint.new
  @shift_pressed = false
  @ctrl_pressed = false
  @alt_pressed = false
  @tab_pressed = false
  @fixed_direction = nil
  @drop_state = 0
  @drawing_plane = :XY
  @last_created_entity = nil

  # Перевірка текстур
  @bounding_box_texture_path ||= Sketchup.find_support_file("_LDSP.png", "Plugins/WWT_CreatePanelsTools/Texturs")
  @edge_texture_path ||= Sketchup.find_support_file("DSP.jpg", "Plugins/WWT_CreatePanelsTools/Texturs")
end

# Оновлюємо обробку клавіші ESC
def onKeyDown(key, repeat, flags, view)
  case key
  when COPY_MODIFIER_KEY
    unless @ctrl_pressed
      @ctrl_pressed = true
      change_drawing_plane
      @ip.clear
      
      if @last_mouse_x != 0 || @last_mouse_y != 0
        @ip.pick(view, @last_mouse_x, @last_mouse_y)
      end
      
      view.invalidate
      draw(view)
    end
  when CONSTRAIN_MODIFIER_KEY
    unless @shift_pressed
      @shift_pressed = true
      view.invalidate
    end
  when TAB_KEY
    unless @tab_pressed
      @tab_pressed = true
      @drop_state = (@drop_state + 1) % 3
      apply_drop_state(view)
      view.invalidate
    end
  when ESC_KEY
    reset_tool
    view.invalidate
  when 13 # Enter key
    if @keyboard_input && @user_width && @user_height
      width_sign = @ip.position.x < @start_point.x ? -1 : 1
      height_sign = @ip.position.y < @start_point.y ? -1 : 1
      # Не конвертуємо тут в міліметри, оскільки @user_width і @user_height вже в міліметрах
      width = @user_width * width_sign
      height = @user_height * height_sign
      end_point = case @drawing_plane
                  when :XY
                    Geom::Point3d.new(@start_point.x + width, @start_point.y + height, @start_point.z)
                  when :XZ
                    Geom::Point3d.new(@start_point.x + width, @start_point.y, @start_point.z + height)
                  when :YZ
                    Geom::Point3d.new(@start_point.x, @start_point.y + width, @start_point.z + height)
                  end
      draw_box(@start_point, end_point, @drop_state * (@object_z / 2), view)
      reset_tool
      view.invalidate
    end
  end
end

def onKeyUp(key, repeat, flags, view)
  case key
  when COPY_MODIFIER_KEY
    @ctrl_pressed = false
    view.invalidate

  when CONSTRAIN_MODIFIER_KEY
    @shift_pressed = false
    @fixed_direction = nil
    view.invalidate

  when TAB_KEY
    @tab_pressed = false
    view.invalidate
  end
end

  def update_vcb
    return unless @start_point && @ip.valid?

    width_cursor, height_cursor = case @drawing_plane
                                  when :XY
                                    [(@ip.position.x - @start_point.x).to_mm, (@ip.position.y - @start_point.y).to_mm]
                                  when :XZ
                                    [(@ip.position.x - @start_point.x).to_mm, (@ip.position.z - @start_point.z).to_mm]
                                  when :YZ
                                    [(@ip.position.y - @start_point.y).to_mm, (@ip.position.z - @start_point.z).to_mm]
                                  end

    # Оновлюємо панель VCB
    Sketchup.vcb_value = "#{width_cursor.round};#{height_cursor.round}"
  end

  def onUserText(text, view)
  # Перевіряємо, який роздільник використовується (';' або '*')
  dimensions = if text.include?(';')
    text.split(';')
  elsif text.include?('*')
    text.split('*')
  else
    [text] # Якщо немає роздільника, повертаємо масив з одним елементом
  end
  
  return unless dimensions.size > 0
  
  width_input = dimensions[0]
  height_input = dimensions[1] || ""
  @keyboard_input = true
  
  # Визначаємо напрямки руху курсора
  cursor_direction = @start_point.vector_to(@ip.position)
  
  # Визначаємо знаки для розмірів в залежності від площини
  case @drawing_plane
  when :XY
    width_sign = cursor_direction.x < 0 ? -1 : 1
    height_sign = cursor_direction.y < 0 ? -1 : 1
  when :XZ
    width_sign = cursor_direction.x < 0 ? -1 : 1
    height_sign = cursor_direction.z < 0 ? -1 : 1
  when :YZ
    width_sign = cursor_direction.y < 0 ? -1 : 1
    height_sign = cursor_direction.z < 0 ? -1 : 1
  end
  
  # Обробка введеної ширини
  if width_input.empty?
    @user_width = nil
  else
    @user_width = width_input.to_f.mm * width_sign
  end
  
  # Обробка введеної висоти
  if height_input.empty?
    @user_height = nil
  else
    @user_height = height_input.to_f.mm * height_sign
  end
  
  view.invalidate
end

def change_drawing_plane
  planes = [:XY, :XZ, :YZ]
  current_index = planes.index(@drawing_plane) || -1
  next_index = (current_index + 1) % planes.length
  @drawing_plane = planes[next_index]
  update_drawing_settings
  
  # Очищаємо InputPoint та форсуємо оновлення
  @ip.clear if @ip
  Sketchup.active_model.active_view.invalidate
end

def update_drawing_settings
  # Змінюємо кольори та параметри відповідно до активної площини
  case @drawing_plane
  when :XY
    @rectungle_color = Sketchup::Color.new(0, 0, 255) # Синій для XY
    @rectungle_line_width = 1
  when :XZ
    @rectungle_color = Sketchup::Color.new(0, 255, 0) # Зелений для XZ
    @rectungle_line_width = 1
  when :YZ
    @rectungle_color = Sketchup::Color.new(255, 0, 0) # Червоний для YZ
    @rectungle_line_width = 1
  end
end

def onMouseMove(flags, x, y, view)
  @last_mouse_x = x
  @last_mouse_y = y
  
  return if @state == -1

  update_edit_transform
  @ip.pick(view, x, y)
  view.invalidate

  if @state == 1 && @start_point
    # Отримуємо локальні координати для обчислення розмірів
    local_cursor_position = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @ip.position
    else
      @ip.position
    end

    local_start_point = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @start_point
    else
      @start_point
    end

    update_vcb
  end

  if @shift_pressed && @start_point
    if @fixed_direction.nil?
      direction_vector = @start_point.vector_to(@ip.position)
      max_axis = [:x, :y, :z].max_by { |axis| direction_vector.send(axis).abs }
      @fixed_direction = max_axis
    end

    local_position = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @ip.position
    else
      @ip.position
    end

    local_start = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @start_point
    else
      @start_point
    end

    case @fixed_direction
    when :x
      local_position.y = local_start.y
      local_position.z = local_start.z
    when :y
      local_position.x = local_start.x
      local_position.z = local_start.z
    when :z
      local_position.x = local_start.x
      local_position.y = local_start.y
    end

    # Трансформуємо назад у глобальні координати
    if @edit_transform && !@edit_transform.identity?
      @ip.position = @edit_transform * local_position
    else
      @ip.position = local_position
    end
  else
    @fixed_direction = nil
  end

  view.invalidate
end

def apply_drop_state(view)
  # Застосовуємо стан падіння для останнього створеного об'єкта
  if @last_created_entity
    drop_distance = @object_z / 2
    transformation = case @drawing_plane
                     when :XY then Geom::Transformation.new([0, 0, -drop_distance])
                     when :XZ then Geom::Transformation.new([0, -drop_distance, 0])
                     when :YZ then Geom::Transformation.new([-drop_distance, 0, 0])
                     end

    case @drop_state
    when 0
      @last_created_entity.transformation = @original_transformation if @original_transformation
    when 1
      @original_transformation = @last_created_entity.transformation unless @original_transformation
      @last_created_entity.transform!(transformation)
    when 2
      @last_created_entity.transformation = @original_transformation if @original_transformation
      double_transformation = transformation * transformation
      @last_created_entity.transform!(double_transformation)
    end
    view.invalidate
  end
end

def onLButtonDown(flags, x, y, view)
  return if @state == -1

  update_edit_transform
  drop_z = @drop_state * (@object_z / 2)

  case @state
  when 0
    @last_created_entity = nil
    # Зберігаємо початкову точку в локальних координатах
    @start_point = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @ip.position
    else
      @ip.position
    end
    @state = 1
    view.invalidate
    update_vcb
  when 1
    cursor_direction = @start_point.vector_to(@ip.position)

    # Отримуємо локальні координати
    local_cursor_position = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @ip.position
    else
      @ip.position
    end

    local_start_point = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @start_point
    else
      @start_point
    end

    case @drawing_plane
    when :XY
      width_sign = local_cursor_position.x < local_start_point.x ? -1 : 1
      height_sign = local_cursor_position.y < local_start_point.y ? -1 : 1
    when :XZ
      width_sign = local_cursor_position.x < local_start_point.x ? -1 : 1
      height_sign = local_cursor_position.z < local_start_point.z ? -1 : 1
    when :YZ
      width_sign = local_cursor_position.y < local_start_point.y ? -1 : 1
      height_sign = local_cursor_position.z < local_start_point.z ? -1 : 1
    end

    if @keyboard_input
      case @drawing_plane
      when :XY
        width = @user_width || ((local_cursor_position.x - local_start_point.x) * width_sign)
        height = @user_height || ((local_cursor_position.y - local_start_point.y) * height_sign)
        width *= width_sign if @user_width.nil?
        height *= height_sign if @user_height.nil?
        end_point = Geom::Point3d.new(
          local_start_point.x + (@user_width || width),
          local_start_point.y + (@user_height || height),
          local_start_point.z
        )
      when :XZ
        width = @user_width || ((local_cursor_position.x - local_start_point.x) * width_sign)
        height = @user_height || ((local_cursor_position.z - local_start_point.z) * height_sign)
        width *= width_sign if @user_width.nil?
        height *= height_sign if @user_height.nil?
        end_point = Geom::Point3d.new(
          local_start_point.x + (@user_width || width),
          local_start_point.y,
          local_start_point.z + (@user_height || height)
        )
      when :YZ
        width = @user_width || ((local_cursor_position.y - local_start_point.y) * width_sign)
        height = @user_height || ((local_cursor_position.z - local_start_point.z) * height_sign)
        width *= width_sign if @user_width.nil?
        height *= height_sign if @user_height.nil?
        end_point = Geom::Point3d.new(
          local_start_point.x,
          local_start_point.y + (@user_width || width),
          local_start_point.z + (@user_height || height)
        )
      end
      
      # Трансформуємо точки назад у глобальні координати
      if @edit_transform && !@edit_transform.identity?
        end_point = @edit_transform * end_point
        start_point_global = @edit_transform * local_start_point
      else
        start_point_global = local_start_point
      end

      # Створюємо групу або компонент
      if @state_object == 0
        draw_box(start_point_global, end_point, drop_z, view)
      else
        draw_component(start_point_global, end_point, drop_z, view)
      end
      
      @keyboard_input = false
    else
      end_point = @ip.position
      
      # Створюємо групу або компонент
      if @state_object == 0
        draw_box(@start_point, end_point, drop_z, view)
      else
        draw_component(@start_point, end_point, drop_z, view)
      end
    end

    reset_partial_tool
    view.invalidate
  end
end

  # Метод `reset_partial_tool`, для часткового скидання інструменту
  def reset_partial_tool
  @state = 0  # Повертаємося до стану початку
  @start_point = nil
  @end_point = nil
  @keyboard_input = false
  @user_width = 0
  @user_height = 0
  @ip.clear
  end

  # Метод для створення фарбованих панелей
  def create_mdf_painted(model)
  # Створюємо або отримуємо матеріал для групи (основного боксу)
  group_mdf_painted = model.materials["_mdf_painted"] || model.materials.add("_mdf_painted")
  group_mdf_painted.color = [255, 240, 255] # RGB колір
  group_mdf_painted.alpha = 1.0

  # Створюємо або отримуємо матеріал для граней
  face_mdf_painted = model.materials["mdf_painted"] || model.materials.add("mdf_painted")
  face_mdf_painted.color = [255, 240, 255] # RGB колір
  face_mdf_painted.alpha = 1.0

  return [group_mdf_painted, face_mdf_painted]
  end

  # Метод для створення скляних матеріалів
  def create_glass_materials(model)
  # Створюємо або отримуємо матеріал для групи (основного боксу)
  group_glass = model.materials["_glass_mat"] || model.materials.add("_glass_mat")
  group_glass.color = [50, 140, 130] # RGB колір
  group_glass.alpha = 0.2  # 20% непрозорість для основного боксу

  # Створюємо або отримуємо матеріал для граней
  face_glass = model.materials["glass_mat"] || model.materials.add("glass_mat")
  face_glass.color = [50, 130, 130] # RGB колір
  face_glass.alpha = 0.6  # 60% непрозорість для граней

  return [group_glass, face_glass]
  end

def add_material_attributes(entity)
  return unless entity && @materials_settings[@panel_material_type]
  
  material_settings = @materials_settings[@panel_material_type]
  
  # Створюємо словник WWT, якщо його ще немає
  entity.attribute_dictionary("WWT", true)
  
  # Базові атрибути
  entity.set_attribute("WWT", "is-board", true)
  entity.set_attribute("WWT", "thickness", @object_z)
  entity.set_attribute("WWT", "name", @object_name)
  entity.set_attribute("WWT", "layer", @layer_name)
  entity.set_attribute("WWT", "ID_panels", material_settings["id"])
  
  # Атрибути з налаштувань матеріалу
  entity.set_attribute("WWT", "material", material_settings["material_code"])
  entity.set_attribute("WWT", "material_type", material_settings["name"])
  
# Атрибути з налаштувань матеріалу
  entity.set_attribute("WWT", "material", material_settings["material_code"])
  entity.set_attribute("WWT", "material_type", material_settings["name"])
  
  # Додаткові атрибути з JSON, якщо вони є
  if material_settings["attributes"]
    material_settings["attributes"].each do |key, value|
      entity.set_attribute("WWT", key, value)
    end
  end
  
  # Спеціальні властивості матеріалу
  if material_settings["material_properties"]
    properties = material_settings["material_properties"]
    properties.each do |prop_name, prop_value|
      entity.set_attribute("WWT", "material_#{prop_name}", prop_value)
    end
  end
end

def verify_texture_paths(material_settings)
  return true unless material_settings && 
                   material_settings["material_type"] == "texture" && 
                   material_settings["texture_paths"]

  main_texture = material_settings["texture_paths"]["main"]
  edge_texture = material_settings["texture_paths"]["edge"]
  
  main_exists = !main_texture.nil? && !main_texture.empty? && 
                File.exist?(get_texture_path(main_texture))
  edge_exists = !edge_texture.nil? && !edge_texture.empty? && 
                File.exist?(get_texture_path(edge_texture))
  
  if !main_exists || !edge_exists
    puts "Попередження: Деякі текстури відсутні для матеріалу #{material_settings['name']}"
  end
  
  main_exists && edge_exists
end

def get_texture_paths
  return [nil, nil] unless @panel_material_type && @materials_settings[@panel_material_type]

  material = @materials_settings[@panel_material_type]
  
  case material["material_type"]
  when "texture"
    return [nil, nil] unless material["texture_paths"]
    
    main_texture = material["texture_paths"]["main"]
    edge_texture = material["texture_paths"]["edge"]
    
    main_path = get_texture_path(main_texture)
    edge_path = get_texture_path(edge_texture)
    
    if main_path && edge_path
      [main_path, edge_path]
    else
      puts "Попередження: Не вдалося знайти текстури для матеріалу #{material['name']}"
      puts "  Головна текстура: #{main_texture}"
      puts "  Текстура ребер: #{edge_texture}"
      [nil, nil]
    end
    
  when "color"
    return [nil, nil] unless material["color_properties"]
    
    [
      {
        color: material["color_properties"]["main"]["color"],
        alpha: material["color_properties"]["main"]["alpha"]
      },
      {
        color: material["color_properties"]["edge"]["color"],
        alpha: material["color_properties"]["edge"]["alpha"]
      }
    ]
  else
    puts "Попередження: Невідомий тип матеріалу #{material['material_type']}"
    [nil, nil]
  end
rescue StandardError => e
  puts "Помилка при отриманні шляхів до текстур: #{e.message}"
  puts e.backtrace
  [nil, nil]
end

# Допоміжний метод для отримання повного шляху до текстури
def get_texture_path(filename)
  return nil if filename.nil? || filename.empty?
  
  search_paths = [
    # Шлях відносно плагіна
    File.join(File.dirname(__FILE__), "Texturs"),
    # Шлях у системній папці плагінів
    File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "Texturs")
  ]
  
  search_paths.each do |base_path|
    if Dir.exist?(base_path)
      full_path = File.join(base_path, filename)
      if File.exist?(full_path)
        puts "Знайдено текстуру: #{full_path}"
        return full_path
      end
    end
  end
  
  puts "Текстуру не знайдено: #{filename}"
  nil
end

def ensure_plugin_directories
  plugin_root = File.dirname(__FILE__)
  ["Texturs", "settings"].each do |dir|
    dir_path = File.join(plugin_root, dir)
    FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)
  end
end

def verify_textures_exist(material_settings)
  return true unless material_settings["material_type"] == "texture"
  
  main_texture = material_settings["texture_paths"]["main"]
  edge_texture = material_settings["texture_paths"]["edge"]
  
  main_path = get_texture_path(main_texture)
  edge_path = get_texture_path(edge_texture)
  
  puts "Перевірка текстур для #{material_settings['name']}:"
  puts "Основна текстура: #{main_path ? 'Знайдено' : 'Не знайдено'}"
  puts "Текстура краю: #{edge_path ? 'Знайдено' : 'Не знайдено'}"
  
  main_path && edge_path && File.exist?(main_path) && File.exist?(edge_path)
end

def apply_material_to_entity(entity, material_properties)
  return unless material_properties && entity
  
  model = Sketchup.active_model
  material = nil

  # Визначаємо тип матеріалу
  material_type = @materials_settings[@panel_material_type]["material_type"]
  
  case material_type
  when "texture"
    # Обробка текстурного матеріалу
    return unless material_properties.is_a?(String) && File.exist?(material_properties)
    
    material_name = File.basename(material_properties, '.*')
    material = model.materials[material_name] || model.materials.add(material_name)
    
    begin
      material.texture = material_properties
    rescue StandardError => e
      puts "Помилка застосування текстури: #{e.message}"
      return
    end
    
  when "color"
    # Обробка кольорового матеріалу
    return unless material_properties.is_a?(Hash) && material_properties[:color]
    
    material_name = "#{@panel_material_type}_#{entity.persistent_id}"
    material = model.materials[material_name] || model.materials.add(material_name)
    
    # Встановлюємо колір та прозорість
    material.color = Sketchup::Color.new(*material_properties[:color])
    material.alpha = material_properties[:alpha] if material_properties[:alpha]
  end
  
  # Застосовуємо матеріал до сутності
  entity.material = material if material && entity.respond_to?(:material=)
  
  # Зберігаємо атрибути матеріалу
  if entity.respond_to?(:attribute_dictionary)
    dict = entity.attribute_dictionary("WWT", true)
    dict["material_type"] = material_type
    dict["material_name"] = @materials_settings[@panel_material_type]["name"]
  end
end

def create_materials_for_panel(model, material_settings)
  materials = {}
  
  case material_settings["material_type"]
  when "texture"
    if material_settings["texture_paths"]
      # Основний матеріал
      main_material_name = "_#{material_settings['name']}"
      main_material = model.materials[main_material_name] || model.materials.add(main_material_name)
      
      # Отримуємо і застосовуємо основну текстуру
      main_texture_path = get_texture_path(material_settings["texture_paths"]["main"])
      if main_texture_path && File.exist?(main_texture_path)
        begin
          main_material.texture = main_texture_path
          puts "Застосовано основну текстуру до #{main_material_name}: #{main_texture_path}"
        rescue => e
          puts "Помилка застосування основної текстури: #{e.message}"
        end
      else
        puts "Не знайдено основну текстуру: #{material_settings["texture_paths"]["main"]}"
      end
      materials[:main] = main_material

      # Матеріал для граней (крайки)
      edge_material_name = material_settings['name']
      edge_material = model.materials[edge_material_name] || model.materials.add(edge_material_name)
      
      # Отримуємо і застосовуємо текстуру крайки
      edge_texture_path = get_texture_path(material_settings["texture_paths"]["edge"])
      if edge_texture_path && File.exist?(edge_texture_path)
        begin
          edge_material.texture = edge_texture_path
          puts "Застосовано текстуру крайки до #{edge_material_name}: #{edge_texture_path}"
        rescue => e
          puts "Помилка застосування текстури крайки: #{e.message}"
        end
      else
        puts "Не знайдено текстуру крайки: #{material_settings["texture_paths"]["edge"]}"
      end
      materials[:edge] = edge_material

      # Додаємо атрибути до матеріалів для відстеження
      [main_material, edge_material].each do |mat|
        next unless mat
        mat.attribute_dictionary('WWT', true)
        mat.set_attribute('WWT', 'material_type', material_settings['material_type'])
        mat.set_attribute('WWT', 'material_name', material_settings['name'])
        mat.set_attribute('WWT', 'is_edge', mat == edge_material)
        
        # Зберігаємо шляхи до текстур в атрибутах
        if mat == main_material
          mat.set_attribute('WWT', 'texture_path', main_texture_path)
        else
          mat.set_attribute('WWT', 'texture_path', edge_texture_path)
        end
      end
    end
    
  when "color"
    # Основний матеріал
    main_material_name = "_#{material_settings['name']}"
    main_material = model.materials[main_material_name] || model.materials.add(main_material_name)
    
    main_props = material_settings["color_properties"]["main"]
    main_material.color = Sketchup::Color.new(*main_props["color"])
    main_material.alpha = main_props["alpha"] if main_props["alpha"]
    materials[:main] = main_material

    # Матеріал для граней
    edge_material_name = material_settings['name']
    edge_material = model.materials[edge_material_name] || model.materials.add(edge_material_name)
    
    edge_props = material_settings["color_properties"]["edge"]
    edge_material.color = Sketchup::Color.new(*edge_props["color"])
    edge_material.alpha = edge_props["alpha"] if edge_props["alpha"]
    materials[:edge] = edge_material
  end

  # Створюємо білий матеріал один раз
  materials[:white] = model.materials["Material"] || begin
    white_material = model.materials.add("Material")
    white_material.color = Sketchup::Color.new(255, 255, 255)
    white_material
  end

  # Перевірка створених матеріалів
  if materials[:main].nil? || materials[:edge].nil?
    puts "Помилка: Не вдалося створити всі необхідні матеріали"
    puts "Основний матеріал: #{materials[:main] ? 'Створено' : 'Відсутній'}"
    puts "Матеріал крайки: #{materials[:edge] ? 'Створено' : 'Відсутній'}"
  end

  materials
end

def verify_and_restore_material_textures(material)
  return unless material
  
  wwt_dict = material.attribute_dictionary('WWT')
  return unless wwt_dict
  
  texture_path = wwt_dict['texture_path']
  if texture_path && File.exist?(texture_path) && !material.texture
    begin
      material.texture = texture_path
      puts "Відновлено текстуру для матеріалу #{material.name}: #{texture_path}"
    rescue => e
      puts "Помилка відновлення текстури для #{material.name}: #{e.message}"
    end
  end
end

def draw_box(start_point, end_point, drop_z, view)
  load_textures_if_needed
  model = Sketchup.active_model
  
  begin
    model.start_operation('Draw Box', true)
    entities = model.active_entities
    layers = model.layers

    material_settings = @materials_settings[@panel_material_type]
    unless material_settings
      puts "Помилка: Не знайдено налаштування матеріалу"
      return model.abort_operation
    end

    unless start_point && end_point
      puts "Помилка: start_point або end_point є nil"
      return model.abort_operation
    end

    puts "start_point: #{start_point.inspect}"
    puts "end_point: #{end_point.inspect}"
    puts "drop_z: #{drop_z.inspect}"
    puts "drawing_plane: #{@drawing_plane.inspect}"

    # Визначаємо розміри
    case @drawing_plane
    when :XY
      width_adjusted = (end_point.x - start_point.x).abs - (@left_gap + @right_gap)
      height_adjusted = (end_point.y - start_point.y).abs - (@top_gap + @bottom_gap)
      x_offset = start_point.x < end_point.x ? @left_gap : -@left_gap - width_adjusted
      y_offset = start_point.y < end_point.y ? @bottom_gap : -@bottom_gap - height_adjusted
      z_offset = -drop_z
    when :XZ
      width_adjusted = (end_point.x - start_point.x).abs - (@left_gap + @right_gap)
      height_adjusted = (end_point.z - start_point.z).abs - (@top_gap + @bottom_gap)
      x_offset = start_point.x < end_point.x ? @left_gap : -@left_gap - width_adjusted
      y_offset = -drop_z
      z_offset = start_point.z < end_point.z ? @bottom_gap : -@bottom_gap - height_adjusted
    when :YZ
      width_adjusted = (end_point.y - start_point.y).abs - (@left_gap + @right_gap)
      height_adjusted = (end_point.z - start_point.z).abs - (@top_gap + @bottom_gap)
      x_offset = -drop_z
      y_offset = start_point.y < end_point.y ? @left_gap : -@left_gap - width_adjusted
      z_offset = start_point.z < end_point.z ? @bottom_gap : -@bottom_gap - height_adjusted
    else
      puts "Помилка: Невідома площина малювання #{@drawing_plane}"
      return model.abort_operation
    end

    unless width_adjusted && height_adjusted
      puts "Помилка: width_adjusted або height_adjusted є nil"
      return model.abort_operation
    end

    if width_adjusted <= 0 || height_adjusted <= 0
      puts "Помилка: Некоректні розміри (width_adjusted: #{width_adjusted}, height_adjusted: #{height_adjusted})"
      return model.abort_operation
    end

    # Створюємо групу
    group = entities.add_group
    group.make_unique

    # Призначаємо шар
    if @layer_name && !@layer_name.strip.empty?
      layer = layers[@layer_name] || layers.add(@layer_name)
      group.layer = layer
    end

    group.name = @object_name

    # Базові атрибути групи
    wwt_dict = group.attribute_dictionary("WWT", true)
    group.set_attribute("WWT", "is_board", true)
    group.set_attribute("WWT", "thickness", @object_z)
    group.set_attribute("WWT", "name", @object_name)
    group.set_attribute("WWT", "layer", @layer_name)
    group.set_attribute("WWT", "material_type", material_settings["material_type"])
    group.set_attribute("WWT", "material_name", material_settings["name"])
    group.set_attribute("WWT", "ID_panels", material_settings["id"])

    # Зберігаємо розміри як атрибути
    case @drawing_plane
    when :XY
      group.set_attribute("WWT", "width", width_adjusted.to_f)
      group.set_attribute("WWT", "height", height_adjusted.to_f)
      group.set_attribute("WWT", "depth", @object_z.to_f)
    when :XZ
      group.set_attribute("WWT", "width", width_adjusted.to_f)
      group.set_attribute("WWT", "height", @object_z.to_f)
      group.set_attribute("WWT", "depth", height_adjusted.to_f)
    when :YZ
      group.set_attribute("WWT", "width", @object_z.to_f)
      group.set_attribute("WWT", "height", width_adjusted.to_f)
      group.set_attribute("WWT", "depth", height_adjusted.to_f)
    end

    # Створюємо геометрію з origin у (0, 0, 0)
    points = create_box_points(0, 0, 0, width_adjusted, height_adjusted)
    faces = create_faces(group.entities, points, @has_edge)

    # Переміщуємо групу до start_point з урахуванням зсувів
    move_vector = Geom::Vector3d.new(
      start_point.x + x_offset,
      start_point.y + y_offset,
      start_point.z + z_offset
    )
    move_transformation = Geom::Transformation.new(move_vector)
    group.transform!(move_transformation)

    # Перевіряємо наявність текстур перед створенням матеріалів
    unless verify_textures_exist(material_settings)
      UI.messagebox("Помилка: Не знайдено необхідні текстури для матеріалу #{material_settings['name']}")
      return model.abort_operation
    end

    # Створюємо всі необхідні матеріали
    materials = create_materials_for_panel(model, material_settings)
    unless materials[:main] && materials[:edge]
      puts "Помилка: Не вдалося створити необхідні матеріали"
      return model.abort_operation
    end

    # Сортуємо грані за площею
    sorted_faces = faces.sort_by(&:area).reverse
    largest_faces = sorted_faces[0..1] # Дві найбільші грані
    edge_faces = sorted_faces[2..-1]   # Всі інші грані (для кромок)

    # Визначаємо верхню і нижню грані для XZ площини
    if @drawing_plane == :XZ
      largest_faces.sort_by! do |face|
        center = face_center(face)
        center.z
      end
    end

    # Застосовуємо матеріали
    group.material = materials[:main]

    if material_settings["sidedness"]["type"] == "Single_sided"
      largest_faces[0].material = materials[:main] if largest_faces[0].valid?
      largest_faces[0].back_material = nil if largest_faces[0].valid?
      largest_faces[0].delete_attribute("WWT", "sidedness_type") if largest_faces[0].valid?
      
      largest_faces[1].material = materials[:white] if largest_faces[1].valid?
      largest_faces[1].back_material = nil if largest_faces[1].valid?
      largest_faces[1].set_attribute("WWT", "sidedness_type", "Single_sided") if largest_faces[1].valid?
    else
      largest_faces.each do |face|
        face.material = materials[:main] if face.valid?
        face.back_material = nil if face.valid?
        face.delete_attribute("WWT", "sidedness_type") if face.valid?
      end
    end

    edge_faces.each do |face|
      next unless face && face.valid? && !face.deleted?
      face.material = materials[:edge]
      face.back_material = nil
      
      if @has_edge
        face.attribute_dictionary("ABF", true)
        face.set_attribute("ABF", "edge-band-id", 0)
      end
    end

    # Фінальні налаштування
    @last_created_entity = group
    @original_transformation = group.transformation.clone

    apply_layer_based_on_material(group)
    materials.values.each { |mat| verify_and_restore_material_textures(mat) }
    # reset_origin_to_bottom_left(group) # Вже не потрібно, бо геометрія створюється правильно

    model.commit_operation
  rescue StandardError => e
    puts "Помилка в методі draw_box: #{e.message}"
    puts e.backtrace.join("\n")
    model.abort_operation
  end
end

def draw_component(start_point, end_point, drop_z, view)
  load_textures_if_needed
  model = Sketchup.active_model
  model.start_operation('Create Component', true)
  entities = model.active_entities
  definitions = model.definitions
  layers = model.layers

  material_settings = @materials_settings[@panel_material_type]
  unless material_settings
    puts "Помилка: Не знайдено налаштування матеріалу"
    return model.abort_operation
  end

  # Перевіряємо наявність текстур перед створенням матеріалів
  unless verify_textures_exist(material_settings)
    UI.messagebox("Помилка: Не знайдено необхідні текстури для матеріалу #{material_settings['name']}")
    return model.abort_operation
  end

  # Створюємо нове визначення компонента
  definition = definitions.add(@object_name)
  definition_entities = definition.entities

  # Визначаємо розміри та позицію
  case @drawing_plane
  when :XY
    width_adjusted  = (end_point.x - start_point.x).abs - (@left_gap + @right_gap)
    height_adjusted = (end_point.y - start_point.y).abs - (@top_gap + @bottom_gap)
    x_start = start_point.x < end_point.x ? @left_gap : -@left_gap - width_adjusted
    y_start = start_point.y < end_point.y ? @bottom_gap : -@bottom_gap - height_adjusted
    z_start = -drop_z
  when :XZ
    width_adjusted  = (end_point.x - start_point.x).abs - (@left_gap + @right_gap)
    height_adjusted = (end_point.z - start_point.z).abs - (@top_gap + @bottom_gap)
    x_start = start_point.x < end_point.x ? @left_gap : -@left_gap - width_adjusted
    y_start = -drop_z
    z_start = start_point.z < end_point.z ? @bottom_gap : -@bottom_gap - height_adjusted
  when :YZ
    width_adjusted  = (end_point.y - start_point.y).abs - (@left_gap + @right_gap)
    height_adjusted = (end_point.z - start_point.z).abs - (@top_gap + @bottom_gap)
    x_start = -drop_z
    y_start = start_point.y < end_point.y ? @left_gap : -@left_gap - width_adjusted
    z_start = start_point.z < end_point.z ? @bottom_gap : -@bottom_gap - height_adjusted
  end

  # Перевірка розмірів
  if width_adjusted <= 0 || height_adjusted <= 0
    model.abort_operation
    return
  end

  # Створення точок та граней
  points = create_box_points(x_start, y_start, z_start, width_adjusted, height_adjusted)
  faces = create_faces(definition_entities, points, @has_edge)

  # Створюємо всі необхідні матеріали
  materials = create_materials_for_panel(model, material_settings)
  return model.abort_operation unless materials[:main] && materials[:edge]

  # Сортуємо грані за площею
  sorted_faces = faces.sort_by(&:area).reverse
  largest_faces = sorted_faces[0..1]
  edge_faces = sorted_faces[2..-1]

  # Визначаємо верхню і нижню грані для XZ площини
  if @drawing_plane == :XZ
    largest_faces.sort_by! do |face|
      center = face_center(face)
      center.z
    end
  end

  # Створення екземпляру компонента
  transformation = Geom::Transformation.new(start_point)
  instance = entities.add_instance(definition, transformation)

  # Додаємо атрибути до компонента
  instance.attribute_dictionary("WWT", true)
  instance.set_attribute("WWT", "is_board", true)
  instance.set_attribute("WWT", "thickness", @object_z)
  instance.set_attribute("WWT", "name", @object_name)
  instance.set_attribute("WWT", "layer", @layer_name)
  instance.set_attribute("WWT", "material_type", material_settings["material_type"])
  instance.set_attribute("WWT", "material_name", material_settings["name"])
  instance.set_attribute("WWT", "ID_panels", material_settings["id"])

  # Зберігаємо розміри як атрибути
  case @drawing_plane
  when :XY
    instance.set_attribute("WWT", "width", width_adjusted.to_f)
    instance.set_attribute("WWT", "height", height_adjusted.to_f)
    instance.set_attribute("WWT", "depth", @object_z.to_f)
  when :XZ
    instance.set_attribute("WWT", "width", width_adjusted.to_f)
    instance.set_attribute("WWT", "height", @object_z.to_f)
    instance.set_attribute("WWT", "depth", height_adjusted.to_f)
  when :YZ
    instance.set_attribute("WWT", "width", @object_z.to_f)
    instance.set_attribute("WWT", "height", width_adjusted.to_f)
    instance.set_attribute("WWT", "depth", height_adjusted.to_f)
  end

  # Застосовуємо матеріали
  instance.material = materials[:main]
  definition.material = materials[:main]

  if material_settings["sidedness"]["type"] == "Single_sided"
    largest_faces[0].material = materials[:main]
    largest_faces[0].delete_attribute("WWT", "sidedness_type")
    
    largest_faces[1].material = materials[:white]
    largest_faces[1].set_attribute("WWT", "sidedness_type", "Single_sided")
  else
    largest_faces.each { |face| face.material = materials[:main] }
  end

  # Застосовуємо edge матеріал до бокових граней
  edge_faces.each do |face|
    next unless face && face.valid? && !face.deleted?
    face.material = materials[:edge]
    if @has_edge
      face.attribute_dictionary("ABF", true)
      face.set_attribute("ABF", "edge-band-id", 0)
    end
  end

  # Скидаємо origin перед фінальними операціями
  reset_origin_to_bottom_left(instance)
  
  @last_created_entity = instance
  @original_transformation = instance.transformation

  # Застосування шарів на основі матеріалу
  apply_layer_based_on_material(instance)

  # Перевіряємо та відновлюємо текстури для всіх матеріалів
  materials.values.each { |mat| verify_and_restore_material_textures(mat) }
  
  model.commit_operation
end

# Допоміжний метод для обчислення центру грані
def face_center(face)
  return nil unless face && face.valid?
  
  sum = Geom::Point3d.new(0, 0, 0)
  vertices = face.vertices
  vertices.each do |vertex|
    sum.x += vertex.position.x
    sum.y += vertex.position.y
    sum.z += vertex.position.z
  end
  
  Geom::Point3d.new(
    sum.x / vertices.length.to_f,
    sum.y / vertices.length.to_f,
    sum.z / vertices.length.to_f
  )
end

def create_faces(entities, points, has_edge = false)
  faces = []
  model = Sketchup.active_model
  white_material = model.materials["Material"] || model.materials.add("Material")
  white_material.color = Sketchup::Color.new(255, 255, 255)

  # Створюємо грані на основі масиву точок
  # Порядок створення однаковий для всіх площин:
  faces = [
    entities.add_face(points[0], points[1], points[2], points[3]),    # Передня/Нижня грань
    entities.add_face(points[4], points[7], points[6], points[5]),    # Задня/Верхня грань
    entities.add_face(points[0], points[4], points[5], points[1]),    # Бічна грань 1
    entities.add_face(points[1], points[5], points[6], points[2]),    # Бічна грань 2
    entities.add_face(points[2], points[6], points[7], points[3]),    # Бічна грань 3
    entities.add_face(points[3], points[7], points[4], points[0])     # Бічна грань 4
  ]

  # Автоматичне орієнтування нормалей граней до центру
  group_bounds_center = Geom::Point3d.new(
    points.map { |p| p.x }.sum / points.length,
    points.map { |p| p.y }.sum / points.length,
    points.map { |p| p.z }.sum / points.length
  )

  faces.each do |face|
    next unless face && face.valid?
    # Встановлюємо загальний атрибут для всіх граней панелі
    face.set_attribute("WWT", "is_panel_face", true)
    
    # Правильно орієнтуємо грані
    vector_to_center = face.bounds.center.vector_to(group_bounds_center)
    face.reverse! if face.normal.dot(vector_to_center) > 0
  end

  # Обробка матеріалів на основі розмірів граней
  sorted_faces = faces.select(&:valid?).sort_by(&:area).reverse
  largest_faces = sorted_faces[0..1]
  
  material_settings = @materials_settings[@panel_material_type]
  is_single_sided = material_settings["sidedness"] &&
                    material_settings["sidedness"]["type"] == "Single_sided"

  faces.each do |face|
    next unless face && face.valid?
    if largest_faces.include?(face)
      if is_single_sided
        if face == largest_faces.last
          face.set_attribute("WWT", "sidedness_type", "Single_sided")
          face.material = white_material
        else
          face.delete_attribute("WWT", "sidedness_type")
          face.material = nil
        end
      else
        face.delete_attribute("WWT", "sidedness_type")
        face.material = nil
      end
    end
  end

  faces
end

# Метод для оновлення трансформації контексту редагування
def update_edit_transform
  model = Sketchup.active_model
  # Отримуємо активний шлях редагування
  active_path = model.active_path
  
  if active_path && !active_path.empty?
    # Якщо ми в режимі редагування, обчислюємо загальну трансформацію
    @edit_transform = Geom::Transformation.new
    active_path.each do |instance|
      @edit_transform = instance.transformation * @edit_transform
    end
  else
    # Якщо ми не в режимі редагування, використовуємо одиничну трансформацію
    @edit_transform = Geom::Transformation.new
  end
end

def create_box_points(x_start, y_start, z_start, width, height)
  depth = @object_z
  
  # Створюємо точки в локальному просторі
  local_points = case @drawing_plane
  when :XY
    [
      [x_start, y_start, z_start],                            # pt0
      [x_start + width, y_start, z_start],                    # pt1
      [x_start + width, y_start + height, z_start],           # pt2
      [x_start, y_start + height, z_start],                   # pt3
      [x_start, y_start, z_start + depth],                    # pt4
      [x_start + width, y_start, z_start + depth],            # pt5
      [x_start + width, y_start + height, z_start + depth],   # pt6
      [x_start, y_start + height, z_start + depth]            # pt7
    ]
  when :XZ
    [
      [x_start, y_start, z_start],
      [x_start + width, y_start, z_start],
      [x_start + width, y_start, z_start + height],
      [x_start, y_start, z_start + height],
      [x_start, y_start + depth, z_start],
      [x_start + width, y_start + depth, z_start],
      [x_start + width, y_start + depth, z_start + height],
      [x_start, y_start + depth, z_start + height]
    ]
  when :YZ
    [
      [x_start, y_start, z_start],
      [x_start, y_start + width, z_start],
      [x_start, y_start + width, z_start + height],
      [x_start, y_start, z_start + height],
      [x_start + depth, y_start, z_start],
      [x_start + depth, y_start + width, z_start],
      [x_start + depth, y_start + width, z_start + height],
      [x_start + depth, y_start, z_start + height]
    ]
  end

  # Трансформуємо точки з урахуванням контексту редагування
  if @edit_transform && !@edit_transform.identity?
    local_points.map { |pt| @edit_transform * Geom::Point3d.new(pt) }
  else
    local_points.map { |pt| Geom::Point3d.new(pt) }
  end
end

def cleanup_unused_materials
  model = Sketchup.active_model
  materials = model.materials
  
  materials.each do |material|
    # Перевіряємо, чи це наш "Material" матеріал
    next unless material.name.start_with?("Material")
    
    # Отримуємо ID_panels матеріалу
    dict = material.attribute_dictionary("WWT")
    next unless dict
    
    id_panels = dict["ID_panels"]
    next unless id_panels
    
    # Перевіряємо, чи є об'єкти з цим ID_panels
    used = false
    model.entities.each do |entity|
      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        entity_dict = entity.attribute_dictionary("WWT")
        if entity_dict && entity_dict["ID_panels"] == id_panels
          used = true
          break
        end
      end
    end
    
    # Видаляємо матеріал, якщо він не використовується
    if !used
      puts "Видалення невикористаного матеріалу: #{material.name} (ID: #{id_panels})"
      materials.remove(material)
    end
  rescue => e
    puts "Помилка при обробці матеріалу #{material.name}: #{e.message}"
  end
end

def apply_texture_to_smallest_faces(faces, edge_material = nil)
  return unless @show_panel_material && faces && !faces.empty?

  model = Sketchup.active_model
  materials = model.materials
  material_settings = @materials_settings[@panel_material_type]
  return unless material_settings

  # Визначаємо бокові грані (ті, що не горизонтальні)
  edge_faces = faces.select do |face|
    normal = face.normal
    # Вважаємо грань боковою, якщо її нормаль має мінімальний компонент по Z
    normal.z.abs < 0.9
  end

  # Застосовуємо матеріал до бокових граней
  case material_settings["material_type"]
  when "texture"
    edge_texture_material = if edge_material
      edge_material
    else
      # Отримуємо шлях до текстури edge з JSON
      edge_texture_path = material_settings["texture_paths"]["edge"]
      unless edge_texture_path && File.exist?(edge_texture_path)
        puts "Помилка: шлях до текстури крайки не знайдено або файл не існує."
        return
      end

      # Отримуємо назву матеріалу для крайки з імені файлу текстури edge (без розширення)
      edge_texture_name = File.basename(edge_texture_path, ".*")

      # Виводимо в консоль шлях та назву матеріалу
      puts "Шлях до текстури крайки: #{edge_texture_path}"
      puts "Назва матеріалу крайки: #{edge_texture_name}"

      # Створюємо новий матеріал з назвою текстури крайки
      materials[edge_texture_name] || begin
        new_material = materials.add(edge_texture_name)
        new_material.texture = edge_texture_path
        if material_settings["texture_size"]
          width = material_settings["texture_size"]["width"].to_f.mm
          height = material_settings["texture_size"]["height"].to_f.mm
          new_material.texture.size = [width, height] if new_material.texture
        end
        new_material
      end
    end

    edge_faces.each do |face|
      next unless face && face.valid? && !face.deleted?
      face.material = edge_texture_material
      if @has_edge
        face.attribute_dictionary("ABF", true)
        face.set_attribute("ABF", "edge-band-id", 0)
      end
    end

  when "color"
    edge_color_material = if edge_material
      edge_material
    else
      # Для кольорових матеріалів назва залишається старою (як у налаштуваннях)
      material_name = "#{material_settings['name']}_edge"
      materials[material_name] || begin
        new_material = materials.add(material_name)
        color_props = material_settings["color_properties"]["edge"]
        new_material.color = Sketchup::Color.new(*color_props["color"])
        new_material.alpha = color_props["alpha"] if color_props["alpha"]
        new_material
      end
    end

    edge_faces.each do |face|
      next unless face && face.valid? && !face.deleted?
      face.material = edge_color_material
      if @has_edge
        face.attribute_dictionary("ABF", true)
        face.set_attribute("ABF", "edge-band-id", 0)
      end
    end
  end

  # Додаємо базові атрибути WWT до бокових граней
  edge_faces.each do |face|
    next unless face && face.valid? && !face.deleted?
    face.attribute_dictionary("WWT", true)
    face.set_attribute("WWT", "material_type", material_settings["material_type"])
    face.set_attribute("WWT", "material_name", material_settings["name"])
  end
end

def draw_group(pt1, pt2, pt3, pt4, pt5, pt6, pt7, pt8, start_point)
  model = Sketchup.active_model
  model.start_operation('Create Group', true)
  entities = model.active_entities
  layers = model.layers

  # Отримуємо налаштування матеріалу
  material_settings = @materials_settings[@panel_material_type]
  return model.abort_operation unless material_settings

  # Створюємо шар і групу
  layer = layers[@layer_name] || layers.add(@layer_name)
  group = entities.add_group
  group.make_unique
  group.layer = layer
  group.name = @object_name

  group_entities = group.entities

  # Створюємо грані
  faces = []
  faces << group_entities.add_face(pt1, pt2, pt3, pt4)
  faces << group_entities.add_face(pt5, pt6, pt7, pt8)
  faces << group_entities.add_face(pt1, pt2, pt6, pt5)
  faces << group_entities.add_face(pt2, pt3, pt7, pt6)
  faces << group_entities.add_face(pt3, pt4, pt8, pt7)
  faces << group_entities.add_face(pt4, pt1, pt5, pt8)

  faces.compact!

  faces.each do |face|
    face.reverse! if face.normal.z < 0
  end

  # Застосовуємо матеріали з налаштувань
  main_texture_path, _ = get_texture_paths
  if main_texture_path && File.exist?(main_texture_path)
    material_name = material_settings["name"]
    material = model.materials[material_name] || model.materials.add(material_name)
    material.texture = main_texture_path
    group.material = material
  end

  # Застосовуємо текстури до граней
  apply_texture_to_smallest_faces(faces)

  group.transform!(Geom::Transformation.translation(start_point))
  @last_created_entity = group
  model.commit_operation
end

def assign_layer_to_entities(entity, layer_name)
  model = Sketchup.active_model
  layers = model.layers
  layer = layers[layer_name] || layers.add(layer_name)

  entities = entity.is_a?(Sketchup::ComponentInstance) ? entity.definition.entities : entity.entities

  entities.each do |e|
    if e.is_a?(Sketchup::Face) || e.is_a?(Sketchup::Edge)
      e.layer = layer
    end
  end
end

def apply_layer_based_on_material(entity)
  material_settings = @materials_settings[@panel_material_type]
  return unless material_settings && material_settings["layer_prefix"]
  
  layer_name = "#{material_settings['layer_prefix']} #{material_settings['name']}"
  assign_layer_to_entities(entity, layer_name)
end

def apply_material_to_faces(faces, material_settings)
  model = Sketchup.active_model
  materials = model.materials
  material_name = material_settings['name']

  # Основний матеріал
  main_material = materials[material_name] || materials.add(material_name)
  main_material.color = 'Beige' # Колір матеріалу (можна налаштувати)

  # Застосування матеріалу до всіх граней
  faces.each do |face|
    face.material = main_material
  end
end

  def fetch_materials
    model = Sketchup.active_model
    materials = model.materials.map(&:name)
    materials.unshift("Default")
    @materials = materials
  end

def apply_material(selected_material)
  # Перевірка, чи матеріал не є "Default"
  if selected_material != "Default"
    # Отримуємо матеріал з активної моделі SketchUp
    material = Sketchup.active_model.materials[selected_material]

    # Якщо матеріал знайдено, зберігаємо його в змінну @selected_material
    @selected_material = material if material
  else
    @selected_material = nil  # Очищаємо змінну, якщо вибрано "Default"
  end
end

def draw(view)
  return unless @ip&.valid?

  # Оновлюємо трансформацію контексту при кожному малюванні
  update_edit_transform

  view.line_width = @shift_pressed ? 2 : 0.5
  view.line_stipple = ""
  view.draw_points([@ip.position], 7, 1, "red")

  if @state == 0
    rectungle(view)
  elsif @state == 1 && @start_point
    drop_z = @drop_state * (@object_z / 2)
    cursor_direction = @start_point.vector_to(@ip.position)

    # Визначаємо напрямки з урахуванням контексту редагування
    local_cursor_position = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @ip.position
    else
      @ip.position
    end

    local_start_point = if @edit_transform && !@edit_transform.identity?
      @edit_transform.inverse * @start_point
    else
      @start_point
    end

    case @drawing_plane
    when :XY
      width_sign = local_cursor_position.x < local_start_point.x ? -1 : 1
      height_sign = local_cursor_position.y < local_start_point.y ? -1 : 1
    when :XZ
      width_sign = local_cursor_position.x < local_start_point.x ? -1 : 1
      height_sign = local_cursor_position.z < local_start_point.z ? -1 : 1
    when :YZ
      width_sign = local_cursor_position.y < local_start_point.y ? -1 : 1
      height_sign = local_cursor_position.z < local_start_point.z ? -1 : 1
    end

    # Розрахунок ширини і висоти
    if @keyboard_input
      case @drawing_plane
      when :XY
        width = @user_width || ((local_cursor_position.x - local_start_point.x) * width_sign)
        height = @user_height || ((local_cursor_position.y - local_start_point.y) * height_sign)
        width *= width_sign if @user_width.nil?
        height *= height_sign if @user_height.nil?
      when :XZ
        width = @user_width || ((local_cursor_position.x - local_start_point.x) * width_sign)
        height = @user_height || ((local_cursor_position.z - local_start_point.z) * height_sign)
        width *= width_sign if @user_width.nil?
        height *= height_sign if @user_height.nil?
      when :YZ
        width = @user_width || ((local_cursor_position.y - local_start_point.y) * width_sign)
        height = @user_height || ((local_cursor_position.z - local_start_point.z) * height_sign)
        width *= width_sign if @user_width.nil?
        height *= height_sign if @user_height.nil?
      end
    else
      case @drawing_plane
      when :XY
        width = local_cursor_position.x - local_start_point.x
        height = local_cursor_position.y - local_start_point.y
      when :XZ
        width = local_cursor_position.x - local_start_point.x
        height = local_cursor_position.z - local_start_point.z
      when :YZ
        width = local_cursor_position.y - local_start_point.y
        height = local_cursor_position.z - local_start_point.z
      end
    end

    adjusted_width = width.abs - (@left_gap + @right_gap)
    adjusted_height = height.abs - (@top_gap + @bottom_gap)
    adjusted_width = 0 if adjusted_width.negative?
    adjusted_height = 0 if adjusted_height.negative?

    # Початкові координати
    case @drawing_plane
    when :XY
      x_start = width >= 0 ? local_start_point.x + @left_gap : local_start_point.x - @left_gap - adjusted_width
      y_start = height >= 0 ? local_start_point.y + @bottom_gap : local_start_point.y - @bottom_gap - adjusted_height
      z_start = local_start_point.z - drop_z
    when :XZ
      x_start = width >= 0 ? local_start_point.x + @left_gap : local_start_point.x - @left_gap - adjusted_width
      y_start = local_start_point.y - drop_z
      z_start = height >= 0 ? local_start_point.z + @bottom_gap : local_start_point.z - @bottom_gap - adjusted_height
    when :YZ
      x_start = local_start_point.x - drop_z
      y_start = width >= 0 ? local_start_point.y + @left_gap : local_start_point.y - @left_gap - adjusted_width
      z_start = height >= 0 ? local_start_point.z + @bottom_gap : local_start_point.z - @bottom_gap - adjusted_height
    end

    # Точки паралелепіпеда
    points = create_box_points(x_start, y_start, z_start, adjusted_width, adjusted_height)

    # Трансформуємо точки назад у глобальні координати для відображення
    points = points.map { |pt| @edit_transform * pt } if @edit_transform && !@edit_transform.identity?

    # Перетворення 3D точок у 2D екранні координати
    screen_pts = points.map { |pt| view.screen_coords(pt) }
    start_screen = view.screen_coords(@start_point)
    ip_screen = view.screen_coords(@ip.position)

    # Малювання граней
    fill_color = case @drawing_plane
                when :XY
                  Sketchup::Color.new(255, 0, 0, 40)
                when :XZ
                  Sketchup::Color.new(0, 255, 0, 40)
                when :YZ
                  Sketchup::Color.new(0, 0, 255, 40)
                end

    line_color = case @drawing_plane
                when :XY
                  Sketchup::Color.new(255, 0, 0)
                when :XZ
                  Sketchup::Color.new(0, 255, 0)
                when :YZ
                  Sketchup::Color.new(0, 0, 255)
                end

    # Малювання граней
    view.drawing_color = fill_color
    view.draw2d(GL_QUADS, [screen_pts[0], screen_pts[1], screen_pts[2], screen_pts[3]])
    view.draw2d(GL_QUADS, [screen_pts[4], screen_pts[5], screen_pts[6], screen_pts[7]])
    view.draw2d(GL_QUADS, [screen_pts[0], screen_pts[1], screen_pts[5], screen_pts[4]])
    view.draw2d(GL_QUADS, [screen_pts[1], screen_pts[2], screen_pts[6], screen_pts[5]])
    view.draw2d(GL_QUADS, [screen_pts[2], screen_pts[3], screen_pts[7], screen_pts[6]])
    view.draw2d(GL_QUADS, [screen_pts[3], screen_pts[0], screen_pts[4], screen_pts[7]])

    # Лінії периметра
    view.line_width = @shift_pressed ? 3 : 1.5
    view.line_stipple = ""
    view.drawing_color = line_color
    
    view.draw2d(GL_LINES, screen_pts[0], screen_pts[1])
    view.draw2d(GL_LINES, screen_pts[1], screen_pts[2])
    view.draw2d(GL_LINES, screen_pts[2], screen_pts[3])
    view.draw2d(GL_LINES, screen_pts[3], screen_pts[0])
    
    view.draw2d(GL_LINES, screen_pts[4], screen_pts[5])
    view.draw2d(GL_LINES, screen_pts[5], screen_pts[6])
    view.draw2d(GL_LINES, screen_pts[6], screen_pts[7])
    view.draw2d(GL_LINES, screen_pts[7], screen_pts[4])
    
    view.draw2d(GL_LINES, screen_pts[0], screen_pts[4])
    view.draw2d(GL_LINES, screen_pts[1], screen_pts[5])
    view.draw2d(GL_LINES, screen_pts[2], screen_pts[6])
    view.draw2d(GL_LINES, screen_pts[3], screen_pts[7])

    # Діагональна лінія
    view.line_width = 1
    view.line_stipple = "-"
    view.drawing_color = line_color
    view.draw2d(GL_LINES, start_screen, ip_screen)

    view.line_stipple = ""
    view.invalidate
  end
end

def rectungle(view)
  return unless @ip&.valid?

  # Діагностичне виведення для відстеження контексту
  active_path = Sketchup.active_model.active_path
  puts "\n=== Контекст редагування ==="
  if active_path && !active_path.empty?
    puts "Знаходимось в контексті редагування"
    editing_context = active_path.last
    puts "Тип контексту: #{editing_context.class}"
    puts "Назва: #{editing_context.name}" if editing_context.respond_to?(:name)
    puts "Трансформація: #{editing_context.transformation}"
    puts "Локальні осі:"
    puts "  X: #{editing_context.transformation.xaxis}"
    puts "  Y: #{editing_context.transformation.yaxis}"
    puts "  Z: #{editing_context.transformation.zaxis}"
  else
    puts "Знаходимось в глобальному просторі моделі"
  end
  puts "========================="

  # Статичне прев'ю навколо поточної точки
  width_in_pixels = 40
  height_in_pixels = 30
  depth = 5.mm

  # Отримуємо базові розміри в моделі
  width = view.pixels_to_model(width_in_pixels, @ip.position)
  height = view.pixels_to_model(height_in_pixels, @ip.position)

  # Отримуємо активний контекст
  if active_path && !active_path.empty?
    editing_context = active_path.last
    transform = editing_context.transformation
    
    # Отримуємо локальні осі напрямків
    x_axis = transform.xaxis
    y_axis = transform.yaxis
    z_axis = transform.zaxis

    # Масштабуємо вектори осей до потрібних розмірів
    x_axis.length = width
    y_axis.length = height
    z_axis.length = depth

    # Створюємо точки використовуючи локальні осі
    case @drawing_plane
    when :XY
      points = [
        @ip.position,
        @ip.position + x_axis,
        @ip.position + x_axis + y_axis,
        @ip.position + y_axis,
        @ip.position + z_axis,
        @ip.position + x_axis + z_axis,
        @ip.position + x_axis + y_axis + z_axis,
        @ip.position + y_axis + z_axis
      ]
    when :XZ
      points = [
        @ip.position,
        @ip.position + x_axis,
        @ip.position + x_axis + z_axis,
        @ip.position + z_axis,
        @ip.position + y_axis,
        @ip.position + x_axis + y_axis,
        @ip.position + x_axis + z_axis + y_axis,
        @ip.position + z_axis + y_axis
      ]
    when :YZ
      points = [
        @ip.position,
        @ip.position + y_axis,
        @ip.position + y_axis + z_axis,
        @ip.position + z_axis,
        @ip.position + x_axis,
        @ip.position + y_axis + x_axis,
        @ip.position + y_axis + z_axis + x_axis,
        @ip.position + z_axis + x_axis
      ]
    end
  else
    # У глобальному просторі використовуємо звичайні координати
    case @drawing_plane
    when :XY
      points = [
        @ip.position,
        @ip.position + Geom::Vector3d.new(width, 0, 0),
        @ip.position + Geom::Vector3d.new(width, height, 0),
        @ip.position + Geom::Vector3d.new(0, height, 0),
        @ip.position + Geom::Vector3d.new(0, 0, depth),
        @ip.position + Geom::Vector3d.new(width, 0, depth),
        @ip.position + Geom::Vector3d.new(width, height, depth),
        @ip.position + Geom::Vector3d.new(0, height, depth)
      ]
    when :XZ
      points = [
        @ip.position,
        @ip.position + Geom::Vector3d.new(width, 0, 0),
        @ip.position + Geom::Vector3d.new(width, 0, height),
        @ip.position + Geom::Vector3d.new(0, 0, height),
        @ip.position + Geom::Vector3d.new(0, depth, 0),
        @ip.position + Geom::Vector3d.new(width, depth, 0),
        @ip.position + Geom::Vector3d.new(width, depth, height),
        @ip.position + Geom::Vector3d.new(0, depth, height)
      ]
    when :YZ
      points = [
        @ip.position,
        @ip.position + Geom::Vector3d.new(0, width, 0),
        @ip.position + Geom::Vector3d.new(0, width, height),
        @ip.position + Geom::Vector3d.new(0, 0, height),
        @ip.position + Geom::Vector3d.new(depth, 0, 0),
        @ip.position + Geom::Vector3d.new(depth, width, 0),
        @ip.position + Geom::Vector3d.new(depth, width, height),
        @ip.position + Geom::Vector3d.new(depth, 0, height)
      ]
    end
  end

  # Перетворення 3D-точок у 2D-екранні координати
  screen_pts = points.map { |pt| view.screen_coords(pt) }

  # Визначення кольорів
  fill_color, line_color = select_colors(@drawing_plane)

  # Малювання граней
  view.drawing_color = fill_color
  view.draw2d(GL_POLYGON, [screen_pts[0], screen_pts[1], screen_pts[2], screen_pts[3]])
  view.draw2d(GL_POLYGON, [screen_pts[4], screen_pts[5], screen_pts[6], screen_pts[7]])

  # Малювання ребер
  view.drawing_color = line_color
  edges = [
    [screen_pts[0], screen_pts[1]], [screen_pts[1], screen_pts[2]],
    [screen_pts[2], screen_pts[3]], [screen_pts[3], screen_pts[0]],
    [screen_pts[4], screen_pts[5]], [screen_pts[5], screen_pts[6]],
    [screen_pts[6], screen_pts[7]], [screen_pts[7], screen_pts[4]],
    [screen_pts[0], screen_pts[4]], [screen_pts[1], screen_pts[5]],
    [screen_pts[2], screen_pts[6]], [screen_pts[3], screen_pts[7]]
  ]
  edges.each { |edge| view.draw2d(GL_LINE_STRIP, edge) }
end

def define_box_points(x_start, y_start, z_start, width, height)
  # Визначення 3D-точок паралелепіпеда
  pt1 = [x_start, y_start, z_start]
  pt2 = [x_start + width, y_start, z_start]
  pt3 = [x_start + width, y_start + height, z_start]
  pt4 = [x_start, y_start + height, z_start]
  pt5 = [pt1[0], pt1[1], pt1[2] + @object_z]
  pt6 = [pt2[0], pt2[1], pt2[2] + @object_z]
  pt7 = [pt3[0], pt3[1], pt3[2] + @object_z]
  pt8 = [pt4[0], pt4[1], pt4[2] + @object_z]
  [pt1, pt2, pt3, pt4, pt5, pt6, pt7, pt8]
end

def select_colors(plane)
  # Вибір кольорів для прев'ю залежно від площини
  case plane
  when :XY
    [Sketchup::Color.new(255, 0, 0, 40), Sketchup::Color.new(255, 0, 0)] # Напівпрозорий червоний
  when :XZ
    [Sketchup::Color.new(0, 255, 0, 40), Sketchup::Color.new(0, 255, 0)] # Напівпрозорий зелений
  when :YZ
    [Sketchup::Color.new(0, 0, 255, 40), Sketchup::Color.new(0, 0, 255)] # Напівпрозорий синій
  end
end

  def load_texture(path)
  # Перевіряємо, чи існує файл за вказаним шляхом
  if File.exist?(path)
    @texture_path = path
  else
  #  puts "Файл текстури не знайдено за шляхом: #{path}"
    @texture_path = nil
  end
  end

def reset_tool(view = Sketchup.active_model.active_view)
  @state = 0
  @start_point = nil
  @end_point = nil
  @keyboard_input = false
  @user_width = 0
  @user_height = 0
  @original_transformation = nil
  @ip.clear
  @shift_pressed = false
  @ctrl_pressed = false
  @alt_pressed = false
  @tab_pressed = false
  @fixed_direction = nil
  @drop_state = 0
  @drawing_plane = :XY
  view.invalidate
end

  # Метод для створення унікальних груп
  def make_groups_unique
  model = Sketchup.active_model
  entities = model.active_entities
  groups = entities.grep(Sketchup::Group)
  groups.each do |group|
    definition = group.definition
    definition.instances.each { |instance| instance.make_unique }
  end
  end

def fetch_layers_with_number_prefix
  begin
    model = Sketchup.active_model
    return [] unless model

    layers = model.layers
    all_layers = layers.to_a.map(&:name).sort

    # Завантажуємо налаштування з JSON
    settings = initialize_default_settings
    return [] unless settings && settings["materials"]

    # Отримуємо унікальні шари з налаштувань матеріалів
    json_layers = settings["materials"].values.map { |m| m["layer_name"] }.compact.uniq

    # Фільтруємо існуючі шари
    filtered_layers = all_layers.select do |name|
      name.match(/^\d+\.(\s|$)/) || name.match(/^\|\s/) || json_layers.include?(name)
    end

    # Якщо немає відповідних шарів, повертаємо шари з JSON
    return filtered_layers unless filtered_layers.empty?

    # Якщо в JSON немає шарів, повертаємо шари за замовчуванням
    if json_layers.empty?
      settings["materials"].values.map { |m| m["layer_name"] }.compact.uniq
    else
      json_layers
    end

  rescue StandardError => e
#    puts "Помилка при отриманні шарів: #{e.message}"
    UI.messagebox("Помилка при отриманні шарів: #{e.message}")
    return []
  end
end

def getMenu(menu)
  # Додаємо пункт меню для виклику діалогу
  menu.add_item("Налаштування панелі") do
    show_dialog
  end
end

# Оновлюємо обробку правої кнопки миші
def onRButtonDown(flags, x, y, view)
  menu = UI::Menu.new
  menu.add_item("Змінити налаштування панелі") do
    show_dialog
  end
  menu.popup(view, x, y)
end

def add_dialog_callbacks
  # Обробка кнопки "ОК"
  @dialog.add_action_callback("accept") do |_, data|
    begin
#      puts "Debug: Отримано дані для збереження: #{data}"
      settings = JSON.parse(data)
      
      # Зберігаємо налаштування
      save_defaults_to_json(settings)
      
      # Застосовуємо налаштування до інструменту
      apply_settings_to_tool(settings)
      
      # Закриваємо діалог
      @dialog.close if @dialog&.visible?
      
      # Створюємо новий екземпляр інструменту і активуємо його
      Sketchup.active_model.select_tool(self.class.new)
      
    rescue JSON::ParserError => e
#      puts "Помилка парсингу JSON: #{e.message}"
      UI.messagebox("Помилка парсингу JSON: #{e.message}")
    rescue StandardError => e
#      puts "Помилка при збереженні налаштувань: #{e.message}"
      UI.messagebox("Помилка при збереженні налаштувань: #{e.message}")
    end
  end

  # Обробка кнопки "Скасувати"
  @dialog.add_action_callback("cancel") do |_|
    @dialog.close if @dialog&.visible?
  end

  # Обробка кнопки "Налаштування"
  @dialog.add_action_callback("open_settings") do |_|
    show_settings_dialog
  end
  
  # Обробка події "ready"
  @dialog.add_action_callback("ready") do |_|
    dialog_data = {
      materials: @materials_settings,
      current_material: @panel_material_type,
      last_used_settings: @current_settings,
      layers: @materials_settings.values.map { |m| m["layer_name"] }.uniq.compact,
      auto_apply: true
    }
    @dialog.execute_script("initializeDialog(#{dialog_data.to_json})")
  end
  
  # Оновлення налаштувань без закриття діалогу
  @dialog.add_action_callback("update_settings") do |_, data|
    begin
      settings = JSON.parse(data)
      save_defaults_to_json(settings)
      apply_settings_to_tool(settings)
    rescue StandardError => e
#      puts "Помилка при оновленні налаштувань: #{e.message}"
      UI.messagebox("Помилка при оновленні налаштувань: #{e.message}")
    end
  end

  # Обробка зміни стану has_edge
  @dialog.add_action_callback("update_has_edge") do |_, data|
    begin
      settings = JSON.parse(data)
      handle_has_edge_update(settings)
    rescue StandardError => e
#      puts "Помилка при оновленні has_edge: #{e.message}"
      UI.messagebox("Помилка при оновленні has_edge: #{e.message}")
    end
  end

  # Обробка зміни режиму sidedness
  @dialog.add_action_callback("update_sidedness") do |_, data|
    begin
      settings = JSON.parse(data)
      handle_sidedness_update(settings["material_key"], settings["sidedness_type"])
    rescue StandardError => e
#      puts "Помилка при оновленні sidedness: #{e.message}"
      UI.messagebox("Помилка при оновленні sidedness: #{e.message}")
    end
  end

end

def handle_sidedness_update(settings)
  file_path = get_file_path("panel_defaults.json")
  current_data = load_defaults_from_json
  
  if material = current_data["materials"][settings["panel_material_type"]]
    material["sidedness"]["type"] = settings["sidedness_type"]
  end
  
  if current_data["last_used_settings"]
    current_data["last_used_settings"]["sidedness_type"] = settings["sidedness_type"]
  else
    current_data["last_used_settings"] = {"sidedness_type" => settings["sidedness_type"]}
  end
  
  File.write(file_path, JSON.pretty_generate(current_data))
  @sidedness_type = settings["sidedness_type"]
  
#  puts "Debug: sidedness оновлено до: #{settings['sidedness_type']}"
#  puts "Debug: Налаштування успішно збережено в JSON"
end

# Винесемо логіку оновлення has_edge в окремий метод
def handle_has_edge_update(settings)
  file_path = get_file_path("panel_defaults.json")
  current_data = load_defaults_from_json
  
  if material = current_data["materials"][settings["panel_material_type"]]
    material["has_edge"] = settings["has_edge"]
  end
  
  if current_data["last_used_settings"]
    current_data["last_used_settings"]["has_edge"] = settings["has_edge"]
  else
    current_data["last_used_settings"] = {"has_edge" => settings["has_edge"]}
  end
  
  File.write(file_path, JSON.pretty_generate(current_data))
  @has_edge = settings["has_edge"]
  
#  puts "Debug: has_edge оновлено до: #{settings['has_edge']}"
#  puts "Debug: Налаштування успішно збережено в JSON"
end

# Ruby метод show_settings_dialog
def show_settings_dialog
  @settings_dialog&.close if @settings_dialog&.visible?

  @settings_dialog = UI::HtmlDialog.new(
    dialog_title: "Налаштування матеріалів",
    preferences_key: "com.WWT.CreatePanelsTools.Settings",
    scrollable: true,
    resizable: true,
    width: 1000,
    height: 600,
    left: 100,
    top: 100
  )

  html_path = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "settings", "settings_dialog.html")
  unless File.exist?(html_path)
    UI.messagebox("HTML-файл налаштувань не знайдено: #{html_path}")
    return
  end

  @settings_dialog.set_file(html_path)

  # Callback для відстеження готовності діалогу
  @settings_dialog.add_action_callback("dialog_ready") do |_|
#    puts "Діалог готовий до роботи"
    load_materials_to_dialog
  end

  # Callback для завантаження матеріалів
  @settings_dialog.add_action_callback("load_materials") do |_|
    begin
#      puts "Початок завантаження матеріалів"
      
      json_path = get_file_path("panel_defaults.json")
#      puts "Шлях до JSON файлу: #{json_path}"
#      puts "JSON файл існує: #{File.exist?(json_path)}"
      
      settings = load_defaults_from_json
#      puts "Завантажені налаштування: #{settings.inspect}"
      
      if settings["materials"]
        materials_data = { "materials" => settings["materials"] }
        js_command = "console.log('Отримані дані:', #{materials_data.to_json}); receiveMaterials(#{materials_data.to_json});"
 #       puts "Виконується JavaScript команда: #{js_command}"
        @settings_dialog.execute_script(js_command)
      else
        error_msg = "Помилка: секція materials відсутня в налаштуваннях"
#        puts error_msg
        UI.messagebox(error_msg)
      end
    rescue StandardError => e
      error_msg = "Помилка при завантаженні налаштувань: #{e.message}\n#{e.backtrace.join("\n")}"
#      puts error_msg
      UI.messagebox(error_msg)
    end
  end

# Оновлений callback для збереження матеріалів
@settings_dialog.add_action_callback("save_materials") do |_, data|
  begin
#    puts "Отримано дані для збереження: #{data}"
    settings = JSON.parse(data)
    
    # Зберігаємо в JSON файл
    file_path = get_file_path("panel_defaults.json")
    current_settings = load_defaults_from_json
    
    # Оновлюємо тільки секцію materials
    current_settings["materials"] = settings["materials"]
    
    # Перевіряємо наявність обов'язкових полів у кожному матеріалі
    settings["materials"].each do |key, material|
      unless material["object_z"] && material["object_name"] && material["gaps"]
        raise "Некоректні дані для матеріалу #{key}"
      end
    end
    
    # Записуємо оновлені налаштування
    File.write(file_path, JSON.pretty_generate(current_settings))
#    puts "Налаштування успішно збережені в #{file_path}"
    
    # Показуємо повідомлення про успішне збереження через JavaScript
    @settings_dialog.execute_script("showSuccess('Налаштування успішно збережені')")
  rescue JSON::ParserError => e
    error_msg = "Помилка парсингу JSON: #{e.message}"
#    puts error_msg
    UI.messagebox(error_msg)
  rescue StandardError => e
    error_msg = "Помилка при збереженні налаштувань: #{e.message}"
#    puts error_msg
    UI.messagebox(error_msg)
  end
end

# Callback для закриття діалогу
@settings_dialog.add_action_callback("cancel_dialog") do |_|
  begin
#    puts "Закриття діалогу налаштувань"
    @settings_dialog.close
  rescue StandardError => e
#    puts "Помилка при закритті діалогу: #{e.message}"
  end
  
  # callback для оновлення налаштувань після збереження
  @settings_dialog.add_action_callback("save_materials") do |_, data|
    begin
      settings = JSON.parse(data)
      
      # Зберігаємо в JSON файл
      file_path = get_file_path("panel_defaults.json")
      current_settings = load_defaults_from_json
      
      # Оновлюємо тільки секцію materials
      current_settings["materials"] = settings["materials"]
      
      # Зберігаємо оновлені налаштування
      File.write(file_path, JSON.pretty_generate(current_settings))
      
      # Оновлюємо налаштування активного інструменту
      reload_settings
      
      @settings_dialog.execute_script("showSuccess('Налаштування успішно збережені')")
    rescue StandardError => e
  #    puts "Помилка при збереженні налаштувань: #{e.message}"
      UI.messagebox("Помилка при збереженні налаштувань: #{e.message}")
    end
  end
  
def reload_settings
  settings = initialize_default_settings
  
  if settings
    @current_settings = settings["last_used_settings"] || {}
    @materials_settings = settings["materials"] || {}
    current_material = settings["current_material"]
    
    if current_material && @materials_settings[current_material]
      material = @materials_settings[current_material]
      
      @panel_material_type = current_material
      @object_z = material["object_z"].to_f.mm
      @object_name = material["object_names"]&.first || "Панель"
      @layer_name = material["layer_name"]
      @gaps = material["gaps"] || [0, 0, 0, 0]
      @left_gap = @gaps[0].to_f.mm
      @right_gap = @gaps[1].to_f.mm
      @top_gap = @gaps[2].to_f.mm
      @bottom_gap = @gaps[3].to_f.mm
      @has_edge = material["has_edge"].nil? ? true : material["has_edge"]
    end
  end
end

def restart_tool
  Sketchup.active_model.select_tool(nil)
  Sketchup.active_model.select_tool(self.class.new)
end
  
end

  # Додаємо метод для завантаження матеріалів
  def load_materials_to_dialog
    begin
#      puts "Початок завантаження матеріалів"
      
      # Отримуємо шлях до JSON файлу
      json_path = get_file_path("panel_defaults.json")
#      puts "Шлях до JSON файлу: #{json_path}"
#      puts "JSON файл існує: #{File.exist?(json_path)}"
      
      # Завантажуємо налаштування
      settings = load_defaults_from_json
#      puts "Завантажені налаштування: #{settings.inspect}"
      
      if settings["materials"]
        materials_data = { "materials" => settings["materials"] }
        js_command = "console.log('Отримані дані:', #{materials_data.to_json}); receiveMaterials(#{materials_data.to_json});"
#        puts "Виконується JavaScript команда: #{js_command}"
        @settings_dialog.execute_script(js_command)
      else
        error_msg = "Помилка: секція materials відсутня в налаштуваннях"
#        puts error_msg
        UI.messagebox(error_msg)
      end
    rescue StandardError => e
      error_msg = "Помилка при завантаженні налаштувань: #{e.message}\n#{e.backtrace.join("\n")}"
 #     puts error_msg
      UI.messagebox(error_msg)
    end
  end

  @settings_dialog.add_action_callback("load_materials") do |_|
    load_materials_to_dialog
  end

  @settings_dialog.show
end

# Метод для завантаження налаштувань
def load_defaults_from_json
  file_path = get_file_path("panel_defaults.json")
  
  unless File.exist?(file_path)
    return create_default_settings
  end

  begin
    JSON.parse(File.read(file_path))
  rescue JSON::ParserError => e
    UI.messagebox("Помилка читання файлу налаштувань: #{e.message}")
    create_default_settings
  end
end

# Новий метод для збереження повних налаштувань
def save_complete_settings(settings)
  file_path = get_file_path("panel_defaults.json")
  begin
    File.write(file_path, JSON.pretty_generate(settings))
  rescue StandardError => e
    UI.messagebox("Помилка збереження налаштувань: #{e.message}")
  end
end

# Метод тут, після методів роботи з налаштуваннями
def add_new_material(data)
  begin
    current_data = load_defaults_from_json
    new_material = JSON.parse(data)
    
    # Перевіряємо обов'язкові поля
    required_fields = ["id", "name", "display_name", "object_names", "object_z", 
                      "layer_name", "gaps", "material_type"]
    
    missing_fields = required_fields.select { |field| !new_material.key?(field) }
    if missing_fields.any?
      raise "Відсутні обов'язкові поля: #{missing_fields.join(', ')}"
    end
    
    # Перевіряємо унікальність ID
    if current_data["materials"].key?(new_material["id"])
      raise "Матеріал з таким ID вже існує"
    end
    
    # Додаємо додаткові поля якщо вони відсутні
    new_material["color_properties"] ||= {
      "main" => {"color" => [255, 255, 255], "alpha" => 1},
      "edge" => {"color" => [255, 255, 255], "alpha" => 1}
    }
    
    new_material["texture_paths"] ||= {"main" => "", "edge" => ""}
    new_material["sidedness"] ||= {"type" => "Double_sided"}
    new_material["has_edge"] ||= false
    
    # Додаємо новий матеріал
    current_data["materials"][new_material["id"]] = new_material
    
    # Зберігаємо оновлені дані
    save_complete_settings(current_data)
    
    # Оновлюємо діалог
    if @settings_dialog && @settings_dialog.visible?
      @settings_dialog.execute_script("receiveMaterials(#{current_data.to_json})")
    end
    
#    puts "Новий матеріал успішно додано: #{new_material['name']}"
  rescue StandardError => e
#    puts "Помилка при додаванні нового матеріалу: #{e.message}"
    UI.messagebox("Помилка при додаванні матеріалу: #{e.message}")
  end
end

def apply_settings_to_tool(settings)
  return unless settings && @materials_settings[settings["panel_material_type"]]

  material = @materials_settings[settings["panel_material_type"]]
  @panel_material_type = settings["panel_material_type"]
  @object_z = settings["object_z"].to_f.mm
  @object_name = settings["object_name"]
  @layer_name = settings["layer_name"]
  @left_gap = settings["left_gap"].to_f.mm
  @right_gap = settings["right_gap"].to_f.mm
  @top_gap = settings["top_gap"].to_f.mm
  @bottom_gap = settings["bottom_gap"].to_f.mm
  @state_object = settings["state_object"] || 0
  @has_edge = settings["has_edge"] || false
  
  # Оновлюємо режим sidedness
  if settings["sidedness_type"]
    material["sidedness"]["type"] = settings["sidedness_type"]
  end

  # Оновлюємо вигляд
  view = Sketchup.active_model.active_view
  view.invalidate if view
end

  def stop_plugin
    Sketchup.active_model.select_tool(nil)
    Sketchup.active_model.selection.clear
    Sketchup.active_model.active_view.invalidate
  end

  def apply_texture_to_face(face, material)
  if face.valid? && !face.deleted?
    face.material = material # Призначаємо матеріал на лицьову сторону
  end
end

def apply_material_to_all_entities(entities, material)
  entities.each do |entity|
    if entity.is_a?(Sketchup::Face)
      apply_texture_to_face(entity, material) # Застосовуємо текстуру до лицьової сторони
    elsif entity.respond_to?(:entities)
      apply_material_to_all_entities(entity.entities, material) # Рекурсивно застосовуємо текстуру до вкладених об'єктів
    end
  end
end

# Метод для отримання шляху до файлу
def get_file_path(file_name)
  plugin_dir = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "settings")
  Dir.mkdir(plugin_dir) unless Dir.exist?(plugin_dir)
  File.join(plugin_dir, file_name)
end

def get_html_file_path(file_name)
  plugin_dir = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "settings")
#  puts "Шлях до каталогу плагіна: #{plugin_dir}" # Виведення шляху до каталогу

  file_path = File.join(plugin_dir, file_name)
#  puts "Шлях до HTML-файлу: #{file_path}" # Виведення повного шляху до файлу

  file_path
end

def show_dialog
  @dialog&.close if @dialog&.visible?

  @dialog = UI::HtmlDialog.new(
    dialog_title: "Налаштування панелі",
    preferences_key: "com.WWT.CreatePanelsTools",
    scrollable: false,
    resizable: true,
    width: 800,
    height: 600,
    left: 100,
    top: 100
  )

  html_path = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "settings", "main_dialog.html")
  unless File.exist?(html_path)
    UI.messagebox("HTML-файл не знайдено: #{html_path}")
    return
  end

  @dialog.set_file(html_path)

  current_settings = load_defaults_from_json
  last_settings = current_settings["last_used_settings"] || {}
  materials = current_settings["materials"] || {}

  # Визначаємо поточний матеріал
  current_material = if last_settings && !last_settings.empty?
    last_settings["panel_material_type"]
  else
    current_settings["current_material"]
  end

  # Формуємо дані для діалогу
  dialog_data = {
    materials: materials,
    current_material: current_material,
    last_used_settings: last_settings,
    layers: materials.values.map { |m| m["layer_name"] }.uniq.compact,
    auto_apply: true
  }

#  puts "Debug: Sending to dialog: #{dialog_data.inspect}"

  @dialog.add_action_callback("ready") do |_|
    @dialog.execute_script("initializeDialog(#{dialog_data.to_json})")
  end

  add_dialog_callbacks
  @dialog.show
end

def select_texture(material_key, texture_type)
  # Відкриваємо діалог вибору файлу з фільтрацією зображень
  file_path = UI.open_file_dialog(
    title: "Оберіть #{texture_type == 'main' ? 'основну' : 'крайову'} текстуру", 
    file_types: ["png", "jpg", "jpeg"],
    file_type_index: 1
  )

  # Перевіряємо, чи обрано файл
  if file_path && File.exist?(file_path)
    # Копіюємо файл до локальної директорії текстур
    textures_dir = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools", "Texturs")
    FileUtils.mkdir_p(textures_dir) unless Dir.exist?(textures_dir)
    
    # Генеруємо нове ім'я файлу (можна додати унікальний префікс або використати оригінальне ім'я)
    filename = File.basename(file_path)
    destination_path = File.join(textures_dir, filename)
    
    # Копіюємо файл
    FileUtils.cp(file_path, destination_path)
    
    # Оновлюємо JSON налаштування
    settings = load_defaults_from_json
    if settings && settings["materials"] && settings["materials"][material_key]
      settings["materials"][material_key]["texture_paths"] ||= {}
      settings["materials"][material_key]["texture_paths"][texture_type] = filename
      
      # Зберігаємо оновлені налаштування
      save_complete_settings(settings)
    end
    
    # Повертаємо шлях до файлу
    filename
  else
    nil
  end
end

def update_dialog_with_materials(dialog, materials)
  return unless dialog && materials

  material_list = materials.keys
  dialog.execute_script("updateMaterialsList(#{material_list.to_json})")
end

def save_defaults_to_json(settings)
  file_path = get_file_path("panel_defaults.json")
  current_data = load_defaults_from_json
  
  # Оновлюємо налаштування, зберігаючи структуру
  current_data["last_used_settings"] = settings
  current_data["current_material"] = settings["panel_material_type"]
  
  # Оновлюємо властивості матеріалу
  if material = current_data["materials"][settings["panel_material_type"]]
    material["object_z"] = settings["object_z"]
    material["layer_name"] = settings["layer_name"]
    material["has_edge"] = settings["has_edge"]
    material["gaps"] = [
      settings["left_gap"],
      settings["right_gap"],
      settings["top_gap"],
      settings["bottom_gap"]
    ]
    
    # Оновлюємо режим sidedness
    material["sidedness"]["type"] = settings["sidedness_type"] if settings["sidedness_type"]
    
    unless material["object_names"].include?(settings["object_name"])
      material["object_names"] << settings["object_name"]
    end
  end

  begin
    File.write(file_path, JSON.pretty_generate(current_data))
  rescue StandardError => e
    UI.messagebox("Помилка збереження налаштувань: #{e.message}")
  end
end

def load_defaults_from_json
  file_path = get_file_path("panel_defaults.json")
  
  unless File.exist?(file_path)
    UI.messagebox("Файл налаштувань не знайдено. Будуть використані налаштування за замовчуванням.")
    return create_default_settings
  end

  begin
    JSON.parse(File.read(file_path))
  rescue JSON::ParserError => e
    UI.messagebox("Помилка читання файлу налаштувань: #{e.message}")
    create_default_settings
  end
end

def initialize_default_settings
  begin
    # Правильний шлях до JSON файлу
    file_path = File.join(Sketchup.find_support_file("Plugins"), 
                         "WWT_CreatePanelsTools", 
                         "settings", 
                         "panel_defaults.json")
    
    unless File.exist?(file_path)
      puts "Файл налаштувань не знайдено: #{file_path}"
      return nil
    end

    json_data = File.read(file_path)
    settings = JSON.parse(json_data)
    
    if settings && settings["materials"]
      return settings
    else
      puts "Помилка: неправильна структура JSON файлу"
      return nil
    end
    
  rescue => e
    puts "Помилка завантаження налаштувань: #{e.message}"
    return nil
  end
end

# Скидаємо початкову точку координат до нижнього лівого кута об'єкта
def reset_origin_to_bottom_left(entity)
  return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
  
  if entity.is_a?(Sketchup::Group)
    # Для груп залишаємо існуючу логіку
    old_transformation = entity.transformation.clone
    bounds = entity.bounds
    new_origin_local = bounds.corner(0)
    new_origin_global = entity.transformation * new_origin_local
    origin_vector = entity.transformation.origin.vector_to(new_origin_global)
    transformation_to_new_origin = Geom::Transformation.translation(origin_vector)
    
    entity.transformation = transformation_to_new_origin
    offset = old_transformation * transformation_to_new_origin.inverse
    entity.entities.transform_entities(offset, entity.entities.to_a)
    
  elsif entity.is_a?(Sketchup::ComponentInstance)
    # Для компонентів використовуємо іншу логіку
    definition = entity.definition
    bounds = definition.bounds
    
    # Зберігаємо оригінальну трансформацію інстанса
    original_transform = entity.transformation
    
    # Знаходимо вектор від поточного origin до нового (лівий нижній кут)
    current_origin = bounds.corner(0)
    
    # Створюємо трансформацію для definition
    definition_transform = Geom::Transformation.translation(current_origin.vector_to(ORIGIN))
    
    # Трансформуємо всі entities в definition
    definition.entities.transform_entities(definition_transform, definition.entities.to_a)
    
    # Оновлюємо трансформацію інстанса, щоб компенсувати зміну definition
    new_transform = original_transform * Geom::Transformation.translation(current_origin)
    entity.transformation = new_transform
  end
end

end  # кінець класу CreateSinglePanel

def self.ensure_plugin_directories
  begin
    plugin_root = File.dirname(__FILE__)
    required_dirs = ["Texturs", "settings"]
    
    required_dirs.each do |dir|
      dir_path = File.join(plugin_root, dir)
      unless Dir.exist?(dir_path)
        FileUtils.mkdir_p(dir_path)
        puts "Створено директорію: #{dir_path}"
      end
    end

    # Перевіряємо також системну папку плагінів
    system_plugin_path = File.join(Sketchup.find_support_file("Plugins"), "WWT_CreatePanelsTools")
    system_dirs = ["Texturs", "settings"].map { |dir| File.join(system_plugin_path, dir) }
    
    system_dirs.each do |dir|
      unless Dir.exist?(dir)
        FileUtils.mkdir_p(dir)
        puts "Створено системну директорію: #{dir}"
      end
    end
  rescue => e
    puts "Помилка при створенні директорій: #{e.message}"
    puts e.backtrace
  end
end

# Методи модуля
def self.run_tool
  Sketchup.active_model.select_tool(CreateSinglePanel.new)
end

def self.add_to_menu(menu)
  menu.add_item("Create Single Panel") { run_tool }
end 

end 
end 

unless file_loaded?(__FILE__)
WWT_CreatePanelsTools::WWT_CreateSinglePanel.ensure_plugin_directories
UI.menu("Plugins").add_item("WWT_Створити панель >>>") {
WWT_CreatePanelsTools::WWT_CreateSinglePanel.run_tool
}
file_loaded(__FILE__)
end

#WWT_CreatePanelsTools::WWT_CreateSinglePanel.run_tool
