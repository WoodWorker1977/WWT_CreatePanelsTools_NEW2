require 'sketchup.rb'
############################# X #########################
class CubeScalerX
  # Перемикачі
  def self.set_scaling_axis(x, y, z)
    @@scale_axes_x = x
    @@scale_axes_y = y
    @@scale_axes_z = z
  end

  def initialize(model)
    @model = model
    @entities = model.active_entities
    @selection = model.selection
  end

def scale_selected_groups
    return if @selection.empty?

# Зберігаємо початкове виділення
    initial_selection = @selection.to_a.dup

    # Видалення з виділення груп, які вже мають сусідів з обох боків по осі X
    @selection.to_a.each do |group|
      if group.is_a?(Sketchup::Group) && (smallest_dimension_is_x?(group) || bounded_by_neighbors_x?(group))
        @selection.remove(group)
      end
    end

    return if @selection.empty?

    @model.start_operation('Масштабування і Переміщення Кубів по осі X', true)

    # Етап 1: Переміщення всіх обраних груп
    @selection.grep(Sketchup::Group).each do |selected_group|
      lower_group, upper_group = find_adjacent_groups_x(selected_group)
      move_group_accordingly_x(lower_group, upper_group, selected_group)
    end

    # Етап 2: Масштабування всіх обраних груп
    @selection.grep(Sketchup::Group).each do |selected_group|
      lower_group, upper_group = find_adjacent_groups_x(selected_group)
      scale_group_between_x(lower_group, upper_group, selected_group)
    end

    @model.commit_operation
    
    # Відновлюємо початкове виділення
    @selection.clear
    @selection.add(initial_selection)
    
    #UI.messagebox('Об\'єкт оптимізовано по осі X')
  end

  private

  def smallest_dimension_is_x?(group)
    bounds = group.bounds
    x_dimension = bounds.width
    [x_dimension, bounds.height, bounds.depth].min == x_dimension
  end

  def bounded_by_neighbors_x?(group)
    lower_group, upper_group = find_adjacent_groups_x(group)
    return false unless lower_group && upper_group

    group_min_x = group.bounds.min.x
    group_max_x = group.bounds.max.x
    lower_group_max_x = lower_group.bounds.max.x
    upper_group_min_x = upper_group.bounds.min.x

    group_min_x == lower_group_max_x && group_max_x == upper_group_min_x
  end

  def find_adjacent_groups_x(selected_group)
    lower_group = upper_group = nil
    min_lower_gap = min_upper_gap = Float::INFINITY

    @entities.grep(Sketchup::Group).each do |group|
      next if group == selected_group || @selection.include?(group)
      next unless groups_intersect_in_yz?(selected_group, group)

      lower_gap = selected_group.bounds.min.x - group.bounds.max.x
      upper_gap = group.bounds.min.x - selected_group.bounds.max.x

      if lower_gap == 0
        lower_group = group unless lower_group && lower_group.bounds.max.x == selected_group.bounds.min.x
      elsif upper_gap == 0
        upper_group = group unless upper_group && upper_group.bounds.min.x == selected_group.bounds.max.x
      else
        if lower_gap > 0 && lower_gap < min_lower_gap
          lower_group = group unless lower_group && lower_group.bounds.max.x == selected_group.bounds.min.x
          min_lower_gap = lower_gap
        elsif upper_gap > 0 && upper_gap < min_upper_gap
          upper_group = group unless upper_group && upper_group.bounds.min.x == selected_group.bounds.max.x
          min_upper_gap = upper_gap
        end
      end
    end

    [lower_group, upper_group]
  end

  def groups_intersect_in_yz?(group1, group2)
    bounds1 = group1.bounds
    bounds2 = group2.bounds

    y_overlap = bounds1.max.y > bounds2.min.y && bounds1.min.y < bounds2.max.y
    z_overlap = bounds1.max.z > bounds2.min.z && bounds1.min.z < bounds2.max.z

    y_overlap && z_overlap
  end

  def move_group_accordingly_x(lower_group, upper_group, selected_group)
    move_transform = nil

    if lower_group && upper_group
      target_center_x = (lower_group.bounds.max.x + upper_group.bounds.min.x) / 2.0
      delta_x = target_center_x - selected_group.bounds.center.x
      move_transform = Geom::Transformation.translation([delta_x, 0, 0])
    elsif lower_group
      gap = selected_group.bounds.min.x - lower_group.bounds.max.x
      move_transform = Geom::Transformation.translation([-gap / 2.0, 0, 0])
    elsif upper_group
      gap = upper_group.bounds.min.x - selected_group.bounds.max.x
      move_transform = Geom::Transformation.translation([gap / 2.0, 0, 0])
    end

    if move_transform
      selected_group.transform!(move_transform)
      return true
    end
    false
  end

  def scale_group_between_x(lower_group, upper_group, selected_group)
    return false unless lower_group && upper_group

    target_width = upper_group.bounds.min.x - lower_group.bounds.max.x
    current_width = selected_group.bounds.width
    scale_factor = target_width / current_width

    if (scale_factor - 1).abs > 0.001
      scale_transform = Geom::Transformation.scaling(selected_group.bounds.center, scale_factor, 1, 1)
      selected_group.transform!(scale_transform)
      return true
    end
    false
  end

  def start_operation(operation_name)
    @model.start_operation(operation_name, true)
  end

  def abort_operation
    @model.abort_operation
  end
end

######################### Y #######################################

class CubeScalerY
  # Перемикачі
  def self.set_scaling_axis(x, y, z)
    @@scale_axes_x = x
    @@scale_axes_y = y
    @@scale_axes_z = z
  end

  def initialize(model)
    @model = model
    @entities = model.active_entities
    @selection = model.selection
  end

  def scale_selected_groups
    return if @selection.empty?

# Зберігаємо початкове виділення
    initial_selection = @selection.to_a.dup

    # Видалення з виділення груп, які вже мають сусідів з обох боків по осі Y
    @selection.to_a.each do |group|
      if group.is_a?(Sketchup::Group) && (smallest_dimension_is_y?(group) || bounded_by_neighbors_y?(group))
        @selection.remove(group)
      end
    end

    return if @selection.empty?

    @model.start_operation('Масштабування і Переміщення Кубів по осі Y', true)

    # Етап 1: Переміщення всіх обраних груп
    @selection.grep(Sketchup::Group).each do |selected_group|
      lower_group, upper_group = find_adjacent_groups_y(selected_group)
      move_group_accordingly_y(lower_group, upper_group, selected_group)
    end

    # Етап 2: Масштабування всіх обраних груп
    @selection.grep(Sketchup::Group).each do |selected_group|
      lower_group, upper_group = find_adjacent_groups_y(selected_group)
      scale_group_between_y(lower_group, upper_group, selected_group)
    end

    @model.commit_operation
    
     # Відновлюємо початкове виділення
    @selection.clear
    @selection.add(initial_selection)
    
    # UI.messagebox('Об\'єкт оптимізовано по осі Y')
  end

  private

  def smallest_dimension_is_y?(group)
    bounds = group.bounds
    y_dimension = bounds.height
    [bounds.width, y_dimension, bounds.depth].min == y_dimension
  end

  def bounded_by_neighbors_y?(group)
    lower_group, upper_group = find_adjacent_groups_y(group)
    return false unless lower_group && upper_group

    group_min_y = group.bounds.min.y
    group_max_y = group.bounds.max.y
    lower_group_max_y = lower_group.bounds.max.y
    upper_group_min_y = upper_group.bounds.min.y

    group_min_y == lower_group_max_y && group_max_y == upper_group_min_y
  end

  def find_adjacent_groups_y(selected_group)
    lower_group = upper_group = nil
    min_lower_gap = min_upper_gap = Float::INFINITY

    @entities.grep(Sketchup::Group).each do |group|
      next if group == selected_group || @selection.include?(group)
      next unless groups_intersect_in_xz?(selected_group, group)

      lower_gap = selected_group.bounds.min.y - group.bounds.max.y
      upper_gap = group.bounds.min.y - selected_group.bounds.max.y

      if lower_gap == 0
        lower_group = group unless lower_group && lower_group.bounds.max.y == selected_group.bounds.min.y
      elsif upper_gap == 0
        upper_group = group unless upper_group && upper_group.bounds.min.y == selected_group.bounds.max.y
      else
        if lower_gap > 0 && lower_gap < min_lower_gap
          lower_group = group unless lower_group && lower_group.bounds.max.y == selected_group.bounds.min.y
          min_lower_gap = lower_gap
        elsif upper_gap > 0 && upper_gap < min_upper_gap
          upper_group = group unless upper_group && upper_group.bounds.min.y == selected_group.bounds.max.y
          min_upper_gap = upper_gap
        end
      end
    end

    [lower_group, upper_group]
  end

  def groups_intersect_in_xz?(group1, group2)
    bounds1 = group1.bounds
    bounds2 = group2.bounds

    x_overlap = bounds1.max.x > bounds2.min.x && bounds1.min.x < bounds2.max.x
    z_overlap = bounds1.max.z > bounds2.min.z && bounds1.min.z < bounds2.max.z

    x_overlap && z_overlap
  end

  def move_group_accordingly_y(lower_group, upper_group, selected_group)
    move_transform = nil

    if lower_group && upper_group
      target_center_y = (lower_group.bounds.max.y + upper_group.bounds.min.y) / 2.0
      delta_y = target_center_y - selected_group.bounds.center.y
      move_transform = Geom::Transformation.translation([0, delta_y, 0])
    elsif lower_group
      gap = selected_group.bounds.min.y - lower_group.bounds.max.y
      move_transform = Geom::Transformation.translation([0, -gap / 2.0, 0])
    elsif upper_group
      gap = upper_group.bounds.min.y - selected_group.bounds.max.y
      move_transform = Geom::Transformation.translation([0, gap / 2.0, 0])
    end

    if move_transform
      selected_group.transform!(move_transform)
      return true
    end
    false
  end

  def scale_group_between_y(lower_group, upper_group, selected_group)
    return false unless lower_group && upper_group

    target_height = upper_group.bounds.min.y - lower_group.bounds.max.y
    current_height = selected_group.bounds.height
    scale_factor = target_height / current_height

    if (scale_factor - 1).abs > 0.001
      scale_transform = Geom::Transformation.scaling(selected_group.bounds.center, 1, scale_factor, 1)
      selected_group.transform!(scale_transform)
      return true
    end
    false
  end

  def start_operation(operation_name)
    @model.start_operation(operation_name, true)
  end

  def abort_operation
    @model.abort_operation
  end
end

##################### Z ###################################

class CubeScalerZ
  # Перемикачі
  def self.set_scaling_axis(x, y, z)
    @@scale_axes_x = x
    @@scale_axes_y = y
    @@scale_axes_z = z
  end

  def initialize(model)
    @model = model
    @entities = model.active_entities
    @selection = model.selection
  end

  def scale_selected_groups
    return if @selection.empty?

# Зберігаємо початкове виділення
    initial_selection = @selection.to_a.dup

    # Видалення з виділення груп, які вже мають сусідів з обох боків по осі Z
    @selection.to_a.each do |group|
      if group.is_a?(Sketchup::Group) && (smallest_dimension_is_z?(group) || bounded_by_neighbors?(group))
        @selection.remove(group)
      end
    end

    return if @selection.empty?

    @model.start_operation('Масштабування і Переміщення Кубів', true)

    # Етап 1: Переміщення всіх обраних груп
    @selection.grep(Sketchup::Group).each do |selected_group|
      lower_group, upper_group = find_adjacent_groups(selected_group)
      move_group_accordingly(lower_group, upper_group, selected_group)
    end

    # Етап 2: Масштабування всіх обраних груп
    @selection.grep(Sketchup::Group).each do |selected_group|
      lower_group, upper_group = find_adjacent_groups(selected_group)
      scale_group_between(lower_group, upper_group, selected_group)
    end

    @model.commit_operation
    
    # Відновлюємо початкове виділення
    @selection.clear
    @selection.add(initial_selection)
    
   # UI.messagebox('Об\'єкт оптимізовано')
  end

  private

def bounded_by_neighbors?(group)
    lower_group, upper_group = find_adjacent_groups(group)
    return false unless lower_group && upper_group

    group_min_z = group.bounds.min.z
    group_max_z = group.bounds.max.z
    lower_group_max_z = lower_group.bounds.max.z
    upper_group_min_z = upper_group.bounds.min.z
    group_min_z == lower_group_max_z && group_max_z == upper_group_min_z
  end

  def smallest_dimension_is_z?(group)
    bounds = group.bounds
    z_dimension = bounds.depth
    [bounds.width, bounds.height, z_dimension].min == z_dimension
  end

  def scale_and_move_group(selected_group)
    lower_group, upper_group = find_adjacent_groups(selected_group)
    moved = move_group_accordingly(lower_group, upper_group, selected_group)
    lower_group, upper_group = find_adjacent_groups(selected_group) if moved
    scaled = scale_group_between(lower_group, upper_group, selected_group)

    return moved, scaled
  end

 def find_adjacent_groups(selected_group)
  lower_group = upper_group = nil
  min_lower_gap = min_upper_gap = Float::INFINITY

  @entities.grep(Sketchup::Group).each do |group|
    next if group == selected_group || @selection.include?(group)
    next unless groups_intersect_in_xy?(selected_group, group)

    lower_gap = selected_group.bounds.min.z - group.bounds.max.z
    upper_gap = group.bounds.min.z - selected_group.bounds.max.z

    # Перевірка, чи межує група впритул з сусідом
    if lower_gap == 0
      lower_group = group unless lower_group && lower_group.bounds.max.z == selected_group.bounds.min.z
    elsif upper_gap == 0
      upper_group = group unless upper_group && upper_group.bounds.min.z == selected_group.bounds.max.z
    else
      if lower_gap > 0 && lower_gap < min_lower_gap
        lower_group = group unless lower_group && lower_group.bounds.max.z == selected_group.bounds.min.z
        min_lower_gap = lower_gap
      elsif upper_gap > 0 && upper_gap < min_upper_gap
        upper_group = group unless upper_group && upper_group.bounds.min.z == selected_group.bounds.max.z
        min_upper_gap = upper_gap
      end
    end
  end

  [lower_group, upper_group]
end


def groups_intersect_in_xy?(group1, group2)
  bounds1 = group1.bounds
  bounds2 = group2.bounds

  x_overlap = bounds1.max.x > bounds2.min.x && bounds1.min.x < bounds2.max.x
  y_overlap = bounds1.max.y > bounds2.min.y && bounds1.min.y < bounds2.max.y

  x_overlap && y_overlap
end

  def move_group_accordingly(lower_group, upper_group, selected_group)
    move_transform = nil

    if lower_group && upper_group
      center_z = (lower_group.bounds.max.z + upper_group.bounds.min.z) / 2.0
      move_transform = Geom::Transformation.translation([0, 0, center_z - selected_group.bounds.center.z])
    elsif lower_group
      gap = selected_group.bounds.min.z - lower_group.bounds.max.z
      move_transform = Geom::Transformation.translation([0, 0, -gap / 2.0])
    elsif upper_group
      gap = upper_group.bounds.min.z - selected_group.bounds.max.z
      move_transform = Geom::Transformation.translation([0, 0, gap / 2.0])
    end

    if move_transform
      selected_group.transform!(move_transform)
      return true
    end
    false
  end

  def scale_group_between(lower_group, upper_group, selected_group)
    return false unless lower_group && upper_group

    target_depth = upper_group.bounds.min.z - lower_group.bounds.max.z
    scale_factor = target_depth.to_f / selected_group.bounds.depth.to_f

    if (scale_factor - 1).abs > 0.001
      scale_transform = Geom::Transformation.scaling(selected_group.bounds.center, 1, 1, scale_factor)
      selected_group.transform!(scale_transform)
      return true
    end
    false
  end

  def start_operation(operation_name)
    @model.start_operation(operation_name, true)
  end

  def abort_operation
    @model.abort_operation
  end
end

################ Меню #####################

# Клас для спостереження за подіями програми
class AppObserver < Sketchup::AppObserver
  def onNewModel(model)
    CubeScalerMenu.add_menu_items
  end
  
  def onOpenModel(model)
    CubeScalerMenu.add_menu_items
  end
end

#Модуль для додавання пунктів меню
module CubeScalerMenu
  @@menu_item_added = false

  def self.add_menu_items
    unless @@menu_item_added
      extensions_menu = UI.menu('Extensions')
      submenu = extensions_menu.add_submenu('WWT_Адаптувати об\'єкти >>>')

      submenu.add_item('- по вісі X') do
        CubeScalerX.set_scaling_axis(true, false, false)
        CubeScalerX.new(Sketchup.active_model).scale_selected_groups
      end
      submenu.add_item('- по вісі Y') do
        CubeScalerY.set_scaling_axis(false, true, false)
        CubeScalerY.new(Sketchup.active_model).scale_selected_groups
      end
      submenu.add_item('- по вісі Z') do
        CubeScalerZ.set_scaling_axis(false, false, true)
        CubeScalerZ.new(Sketchup.active_model).scale_selected_groups
      end

      @@menu_item_added = true
    end
  end
end

# Реєстрація колбеку для автоматичного додавання меню при завантаженні
unless file_loaded?(__FILE__)
  # Додаємо обробник події завантаження розширення
  Sketchup.add_observer(AppObserver.new)
  
  # Додаємо меню при завантаженні
  CubeScalerMenu.add_menu_items
  
  # Позначаємо файл як завантажений
  file_loaded(__FILE__)
end
