require 'sketchup.rb'

module WWT_Dividers
  class Divide
    def initialize(model)
      @model = model
      @entities = model.active_entities
      @selection = model.selection
      @devide_x = true
      @devide_y = true
      @devide_z = true
    end

    def devide_selected_objects
      return if @selection.empty?
      
      start_operation("Divide Objects")
      begin
        distribute_objects
        commit_operation
      rescue => e
        puts "Помилка: #{e.message}"
        puts e.backtrace
        abort_operation
      end
    end

    def distribute_objects
      distribute_objects_along_axis("x") if @devide_x
      distribute_objects_along_axis("y") if @devide_y
      distribute_objects_along_axis("z") if @devide_z
    end

    def valid_object?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    def distribute_objects_along_axis(axis)
      valid_selection = @selection.select { |entity| valid_object?(entity) }
      return if valid_selection.length < 3
      
      axis_index = {"x" => 0, "y" => 1, "z" => 2}[axis]
      
      # Сортуємо об'єкти за їх початковою позицією
      sorted_objects = valid_selection.sort_by { |obj| obj.bounds.min[axis_index] }
      
      # Визначаємо загальну доступну відстань
      start_pos = sorted_objects.first.bounds.min[axis_index]
      end_pos = sorted_objects.last.bounds.max[axis_index]
      total_distance = end_pos - start_pos
      
      # Обчислюємо загальну довжину об'єктів
      total_object_length = valid_selection.sum do |obj| 
        obj.bounds.max[axis_index] - obj.bounds.min[axis_index]
      end
      
      # Обчислюємо розмір проміжку
      gap_size = (total_distance - total_object_length) / (valid_selection.length - 1)
      
      # Розставляємо об'єкти
      current_pos = start_pos
      sorted_objects.each_with_index do |obj, index|
        next if index == 0 # Пропускаємо перший об'єкт
        
        # Обчислюємо нову позицію
        object_length = obj.bounds.max[axis_index] - obj.bounds.min[axis_index]
        target_pos = start_pos
        
        # Додаємо довжини попередніх об'єктів та проміжки
        0.upto(index - 1) do |i|
          prev_obj = sorted_objects[i]
          prev_length = prev_obj.bounds.max[axis_index] - prev_obj.bounds.min[axis_index]
          target_pos += prev_length + gap_size
        end
        
        # Створюємо вектор переміщення
        current_pos = obj.bounds.min[axis_index]
        move_vector = Geom::Vector3d.new(0, 0, 0)
        move_vector[axis_index] = target_pos - current_pos
        
        # Переміщуємо об'єкт
        transform = Geom::Transformation.translation(move_vector)
        obj.transform!(transform)
      end
    end

    def self.activate_devide(axis)
      model = Sketchup.active_model
      divider = Divide.new(model)
      divider.set_axis(axis)
      divider.devide_selected_objects
    end

    def set_axis(axis)
      @devide_x = axis == "x"
      @devide_y = axis == "y"
      @devide_z = axis == "z"
    end

    private

    def start_operation(operation_name)
      @model.start_operation(operation_name, true)
    end

    def commit_operation
      @model.commit_operation
    end

    def abort_operation
      @model.abort_operation
    end
  end

  unless file_loaded?(__FILE__)
    # Змінюємо назву меню, щоб відобразити нову функціональність
    divide_menu = UI.menu("Extensions").add_submenu("WWT_Розподілити об'єкти рівномірно >>>")
    divide_menu.add_item("по вісі X") { Divide.activate_devide("x") }
    divide_menu.add_item("по вісі Y") { Divide.activate_devide("y") }
    divide_menu.add_item("по вісі Z") { Divide.activate_devide("z") }
    file_loaded(__FILE__)
  end
end