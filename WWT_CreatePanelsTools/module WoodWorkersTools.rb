module WoodWorkersTools
  @intersection_active = false
  @intersection_data = [] # Дані перетинів: [{obj1_id, obj2_id, faces, edges}]
  @tracked_objects = {}   # Словник об'єктів із перетинами: {entityID => entity}
  @model_observer = nil
  @updating = false       # Прапорець для запобігання рекурсії
  @initialized = false    # Прапорець ініціалізації
  
  # Клас оверлея для малювання перетинів
  class IntersectionOverlay < Sketchup::Overlay
    # Константи для налаштувань
    FILL_COLOR = Sketchup::Color.new(255, 0, 0, 100)
    EDGE_COLOR = Sketchup::Color.new(255, 0, 0, 255)
    LINE_WIDTH = 3
    
    def initialize
      super('IntersectionOverlay', 'Підсвічування перетинів між компонентами')
    end
    
    def draw(view)
      return unless WoodWorkersTools.intersection_monitor_active?
      
      intersection_data = WoodWorkersTools.instance_variable_get(:@intersection_data)
      return if intersection_data.nil? || intersection_data.empty?
      
      begin
        # Малювання заповнення перетинів
        intersection_data.each do |data|
          data[:faces].each do |face_vertices|
            next if face_vertices.size < 3
            # Малюємо заповнення перетину
            view.drawing_color = FILL_COLOR
            view.draw(GL_POLYGON, face_vertices)
          end
          
          # Малюємо границі перетину
          view.drawing_color = EDGE_COLOR
          view.line_width = LINE_WIDTH
          
          data[:edges].each do |edge|
            start_pos, end_pos = edge
            view.draw(GL_LINES, [start_pos, end_pos])
          end
        end
      rescue => e
        puts "Помилка при малюванні перетинів: #{e.message}"
      end
    end
  end
  
  # Спостерігач моделі
  class IntersectionModelObserver < Sketchup::ModelObserver
    def onTransactionCommit(model)
      WoodWorkersTools.update_affected_intersections(model)
    end
    
    def onTransactionUndo(model)
      WoodWorkersTools.update_affected_intersections(model)
    end
    
    def onTransactionRedo(model)
      WoodWorkersTools.update_affected_intersections(model)
    end
    
    def onActivePathChanged(model)
      WoodWorkersTools.update_affected_intersections(model)
    end
  end
  
  # Ініціалізація оверлея
  def self.initialize_overlay
    model = Sketchup.active_model
    return unless model
    
    @overlay = IntersectionOverlay.new
    model.overlays.add(@overlay)
  end
  
  # Активація моніторингу
  def self.start_intersection_monitor
    return if @intersection_active
    model = Sketchup.active_model
    return unless model
    
    puts "Активація моніторингу перетинів..."
    @intersection_active = true
    
    # Ініціалізуємо оверлей, якщо ще не був створений
    initialize_overlay if @overlay.nil?
    
    # Початкове обчислення перетинів
    initial_intersections(model)
    
    # Додаємо спостерігач моделі
    @model_observer = IntersectionModelObserver.new
    model.add_observer(@model_observer)
    
    puts "Моніторинг перетинів увімкнено"
    model.active_view.invalidate
    nil
  end
  
  # Зупинка моніторингу
  def self.stop_intersection_monitor
    puts "Зупинка моніторингу перетинів..."
    model = Sketchup.active_model
    if model
      model.remove_observer(@model_observer) if @model_observer
      # Не видаляємо оверлей, просто очищаємо дані перетинів
    end
    
    @model_observer = nil
    @intersection_active = false
    @intersection_data = []
    @tracked_objects = {}
    @updating = false
    model&.active_view&.invalidate
    puts "Моніторинг перетинів вимкнено"
    nil
  end
  
  # Початкове обчислення перетинів
  def self.initial_intersections(model)
    entities = model.active_entities
    entities = model.entities if entities.length.zero? && model.active_path
    
    groups_and_components = entities.select { |e| !e.deleted? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) }
    puts "Знайдено #{groups_and_components.size} груп/компонентів"
    
    @intersection_data = []
    intersection_count = 0
    
    groups_and_components.combination(2).each do |obj1, obj2|
      next if obj1.deleted? || obj2.deleted?
      if bounds_intersect?(obj1.bounds, obj2.bounds) && !bounds_touching?(obj1.bounds, obj2.bounds)
        faces, edges = calculate_exact_intersection(obj1, obj2)
        unless faces.empty?
          @intersection_data << { obj1_id: obj1.entityID, obj2_id: obj2.entityID, faces: faces, edges: edges }
          @tracked_objects[obj1.entityID] = obj1
          @tracked_objects[obj2.entityID] = obj2
          intersection_count += 1
          puts "Перетин між #{obj1.entityID} і #{obj2.entityID}"
        end
      end
    end
    
    puts "Знайдено #{intersection_count} перетинів"
    Sketchup::set_status_text("Перетинів: #{intersection_count}")
    model.active_view.invalidate if model.active_view
  end
  
  # Оновлення перетинів для змінених об'єктів
  def self.update_affected_intersections(model)
    return unless @intersection_active
    return if @intersection_data.empty?
    return if @updating # Запобігаємо рекурсії
    
    @updating = true
    puts "Оновлення перетинів після змін..."
    
    updated_data = []
    
    @intersection_data.each do |data|
      obj1 = @tracked_objects[data[:obj1_id]]
      obj2 = @tracked_objects[data[:obj2_id]]
      
      # Перевіряємо, чи об'єкти все ще існують
      if obj1 && obj2 && !obj1.deleted? && !obj2.deleted?
        if bounds_intersect?(obj1.bounds, obj2.bounds) && !bounds_touching?(obj1.bounds, obj2.bounds)
          faces, edges = calculate_exact_intersection(obj1, obj2)
          unless faces.empty?
            updated_data << { obj1_id: obj1.entityID, obj2_id: obj2.entityID, faces: faces, edges: edges }
          else
            puts "Перетин між #{obj1.entityID} і #{obj2.entityID} зник"
          end
        else
          puts "Перетин між #{obj1.entityID} і #{obj2.entityID} зник"
        end
      end
    end
    
    # Пошук нових перетинів серед активних об'єктів
    entities = model.active_entities
    entities = model.entities if entities.length.zero? && model.active_path
    
    groups_and_components = entities.select { |e| !e.deleted? && (e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) }
    
    # Додаємо нові перетини, щоб не пропустити
    groups_and_components.combination(2).each do |obj1, obj2|
      next if obj1.deleted? || obj2.deleted?
      next if updated_data.any? { |data| (data[:obj1_id] == obj1.entityID && data[:obj2_id] == obj2.entityID) || 
                                          (data[:obj1_id] == obj2.entityID && data[:obj2_id] == obj1.entityID) }
      
      if bounds_intersect?(obj1.bounds, obj2.bounds) && !bounds_touching?(obj1.bounds, obj2.bounds)
        faces, edges = calculate_exact_intersection(obj1, obj2)
        unless faces.empty?
          updated_data << { obj1_id: obj1.entityID, obj2_id: obj2.entityID, faces: faces, edges: edges }
          @tracked_objects[obj1.entityID] = obj1
          @tracked_objects[obj2.entityID] = obj2
          puts "Новий перетин між #{obj1.entityID} і #{obj2.entityID}"
        end
      end
    end
    
    @intersection_data = updated_data
    Sketchup::set_status_text("Перетинів: #{@intersection_data.size}")
    model.active_view.invalidate if model.active_view
    @updating = false
  rescue => e
    puts "Помилка оновлення перетинів: #{e.message}"
    @updating = false
  end
  
  # Обчислення перетину (з temp_group)
  def self.calculate_exact_intersection(obj1, obj2)
    faces = []
    edges = []
    return [faces, edges] if obj1.deleted? || obj2.deleted?
    
    model = Sketchup.active_model
    
    temp_group1 = model.entities.add_group
    temp_entities1 = temp_group1.entities
    obj1.entities.each do |entity|
      if entity.is_a?(Sketchup::Face) && !entity.deleted?
        vertices = entity.vertices.map { |v| v.position.transform(obj1.transformation) }
        temp_entities1.add_face(vertices) rescue nil
      end
    end
    temp_entities1.intersect_with(true, Geom::Transformation.new, temp_entities1, Geom::Transformation.new, true, obj2)
    
    temp_group2 = model.entities.add_group
    temp_entities2 = temp_group2.entities
    obj2.entities.each do |entity|
      if entity.is_a?(Sketchup::Face) && !entity.deleted?
        vertices = entity.vertices.map { |v| v.position.transform(obj2.transformation) }
        temp_entities2.add_face(vertices) rescue nil
      end
    end
    temp_entities2.intersect_with(true, Geom::Transformation.new, temp_entities2, Geom::Transformation.new, true, obj1)
    
    bounds1 = obj1.bounds
    bounds2 = obj2.bounds
    [temp_entities1, temp_entities2].each do |entities|
      entities.grep(Sketchup::Face).each do |face|
        next if face.deleted?
        center = face.bounds.center
        if bounds1.contains?(center) && bounds2.contains?(center)
          face_vertices = face.vertices.map(&:position)
          faces << face_vertices if face_vertices.size >= 3
        end
      end
      entities.grep(Sketchup::Edge).each do |edge|
        next if edge.deleted?
        start_pos = edge.start.position
        end_pos = edge.end.position
        if bounds1.contains?(start_pos) && bounds2.contains?(start_pos) &&
           bounds1.contains?(end_pos) && bounds2.contains?(end_pos)
          edges << [start_pos, end_pos]
        end
      end
    end
    
    faces.uniq! { |f| f.map(&:to_s).sort }
    edges.uniq! { |e| [e[0].to_s, e[1].to_s].sort }
    model.entities.erase_entities(temp_group1, temp_group2)
    
    [faces, edges]
  rescue => e
    puts "Помилка обчислення перетину: #{e.message}"
    [faces, edges]
  end
  
  # Перевірка меж
  def self.bounds_intersect?(bounds1, bounds2)
    return false unless bounds1 && bounds2
    !(bounds1.max.x < bounds2.min.x || bounds1.min.x > bounds2.max.x ||
      bounds1.max.y < bounds2.min.y || bounds1.min.y > bounds2.max.y ||
      bounds1.max.z < bounds2.min.z || bounds1.min.z > bounds2.max.z)
  rescue
    false
  end
  
  def self.bounds_touching?(bounds1, bounds2)
    return false unless bounds1 && bounds2
    epsilon = 0.001
    touching_x = (bounds1.max.x - bounds2.min.x).abs < epsilon || (bounds2.max.x - bounds1.min.x).abs < epsilon
    touching_y = (bounds1.max.y - bounds2.min.y).abs < epsilon || (bounds2.max.y - bounds1.min.y).abs < epsilon
    touching_z = (bounds1.max.z - bounds2.min.z).abs < epsilon || (bounds2.max.z - bounds1.min.z).abs < epsilon
    
    if touching_x
      bounds_overlapping_excluding_one_axis?(bounds1, bounds2, :x)
    elsif touching_y
      bounds_overlapping_excluding_one_axis?(bounds1, bounds2, :y)
    elsif touching_z
      bounds_overlapping_excluding_one_axis?(bounds1, bounds2, :z)
    else
      false
    end
  rescue
    false
  end
  
  def self.bounds_overlapping_excluding_one_axis?(bounds1, bounds2, excluded_axis)
    case excluded_axis
    when :x
      (bounds1.min.y <= bounds2.max.y && bounds1.max.y >= bounds2.min.y) &&
      (bounds1.min.z <= bounds2.max.z && bounds1.max.z >= bounds2.min.z)
    when :y
      (bounds1.min.x <= bounds2.max.x && bounds1.max.x >= bounds2.min.x) &&
      (bounds1.min.z <= bounds2.max.z && bounds1.max.z >= bounds2.min.z)
    when :z
      (bounds1.min.x <= bounds2.max.x && bounds1.max.x >= bounds2.min.x) &&
      (bounds1.min.y <= bounds2.max.y && bounds1.max.y >= bounds2.min.y)
    else
      false
    end
  rescue
    false
  end
  
  # Перемикач стану
  def self.toggle_intersection_monitor
    result = @intersection_active ? stop_intersection_monitor : start_intersection_monitor
    # Оновлюємо відображення в будь-якому випадку
    Sketchup.active_model&.active_view&.invalidate
    UI.refresh_toolbars if defined?(UI.refresh_toolbars)
    result
  end
  
  def self.intersection_monitor_active?
    @intersection_active
  end
  
  # Отримання екземпляру оверлея
  def self.overlay
    @overlay
  end
  
  # Тулбар з чекбоксом
  def self.create_toolbar
    @toolbar ||= UI::Toolbar.new("Моніторинг перетинів")
    
    cmd = UI::Command.new("Моніторинг перетинів") {
      WoodWorkersTools.toggle_intersection_monitor
    }
    
    # Спробуємо завантажити стандартну іконку SketchUp, якщо не вдається - використаємо просту
    begin
      cmd.small_icon = "Intersect.png"
      cmd.large_icon = "Intersect.png"
    rescue
      # Якщо стандартна іконка недоступна, використаємо червоний прямокутник
      cmd.small_icon = create_simple_icon(16)
      cmd.large_icon = create_simple_icon(24)
    end
    
    cmd.tooltip = "Увімкнути/вимкнути моніторинг перетинів"
    cmd.status_bar_text = "Увімкнути або вимкнути моніторинг перетинів між групами та компонентами"
    cmd.set_validation_proc {
      WoodWorkersTools.intersection_monitor_active? ? MF_CHECKED : MF_UNCHECKED
    }
    
    @toolbar.add_item(cmd) unless @toolbar.get_last_state > 0
    @toolbar.restore
    @toolbar
  end
  
  # Створення простої іконки (запасний варіант)
  def self.create_simple_icon(size)
    if Sketchup.version.to_i >= 16
      # Для SketchUp 2016 і новіших
      icon = UI::Create.image(size, size)
      icon.transparent = true
      
      # Заповнюємо червоним кольором
      (0...size).each do |x|
        (0...size).each do |y|
          icon.set_rgba_pixel(x, y, 255, 0, 0, 255)
        end
      end
      
      icon
    else
      # Для старіших версій, використаємо nil, щоб SketchUp застосував стандартну іконку
      nil
    end
  end
  
  # Ініціалізація плагіна
  def self.initialize_plugin
    return if @initialized
    
    if Sketchup.active_model
      begin
        initialize_overlay
        create_toolbar
        @initialized = true
        puts "Плагін моніторингу перетинів успішно ініціалізовано"
      rescue => e
        puts "Помилка ініціалізації плагіна: #{e.message}"
        puts e.backtrace.join("\n")
      end
    end
  end
end

# Меню
unless defined?(@intersection_monitor_menu_added)
  @intersection_monitor_menu_added = true
  monitor_menu = UI.menu("Plugins").add_submenu("Моніторинг перетинів")
  
  monitor_menu.add_item("Увімкнути") { WoodWorkersTools.start_intersection_monitor }
  monitor_menu.add_item("Вимкнути") { WoodWorkersTools.stop_intersection_monitor }
  monitor_menu.add_item("Перемкнути стан") { WoodWorkersTools.toggle_intersection_monitor }
end

# Автозапуск
UI.start_timer(1, false) { 
  WoodWorkersTools.initialize_plugin
}