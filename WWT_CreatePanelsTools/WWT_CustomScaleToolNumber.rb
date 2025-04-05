require 'sketchup.rb'

module WWT_CustomScaleToolNumber
  class LockPointsTool
    def initialize(entity)
      @entity = entity
      @bounds = entity.bounds
      @dictionary = entity.attribute_dictionary("SU", false)
    end

    def activate
      Sketchup.active_model.active_view.invalidate
    end

    def draw(view)
      return unless @dictionary

      offset = 1.mm
      lock_x = @dictionary["lock_x"] == true
      lock_y = @dictionary["lock_y"] == true
      lock_z = @dictionary["lock_z"] == true

      min = @bounds.min
      max = @bounds.max
      center_x = (min.x + max.x) / 2
      center_y = (min.y + max.y) / 2
      center_z = (min.z + max.z) / 2

      if lock_x
        draw_point(view, Geom::Point3d.new(min.x - offset, center_y, center_z), lock_x, false, false)
        draw_point(view, Geom::Point3d.new(max.x + offset, center_y, center_z), lock_x, false, false)
      end

      if lock_y
        draw_point(view, Geom::Point3d.new(center_x, min.y - offset, center_z), false, lock_y, false)
        draw_point(view, Geom::Point3d.new(center_x, max.y + offset, center_z), false, lock_y, false)
      end

      if lock_z
        draw_point(view, Geom::Point3d.new(center_x, center_y, min.z - offset), false, false, lock_z)
        draw_point(view, Geom::Point3d.new(center_x, center_y, max.z + offset), false, false, lock_z)
      end
    end

    private

    def draw_point(view, point, lock_x, lock_y, lock_z)
      cross_size = 1
      half_size = cross_size / 2.0
      view.drawing_color = "red"
      view.line_width = 5

      if lock_x
        start_point_x1 = Geom::Point3d.new(point.x, point.y - half_size, point.z)
        end_point_x1 = Geom::Point3d.new(point.x, point.y + half_size, point.z)

        start_point_x2 = Geom::Point3d.new(point.x, point.y, point.z - half_size)
        end_point_x2 = Geom::Point3d.new(point.x, point.y, point.z + half_size)

        view.draw(GL_LINES, [start_point_x1, end_point_x1, start_point_x2, end_point_x2])
      end

      if lock_y
        start_point_y1 = Geom::Point3d.new(point.x, point.y, point.z - half_size)
        end_point_y1 = Geom::Point3d.new(point.x, point.y, point.z + half_size)

        start_point_y2 = Geom::Point3d.new(point.x - half_size, point.y, point.z)
        end_point_y2 = Geom::Point3d.new(point.x + half_size, point.y, point.z)

        view.draw(GL_LINES, [start_point_y1, end_point_y1, start_point_y2, end_point_y2])
      end

      if lock_z
        start_point_z1 = Geom::Point3d.new(point.x, point.y - half_size, point.z)
        end_point_z1 = Geom::Point3d.new(point.x, point.y + half_size, point.z)

        start_point_z2 = Geom::Point3d.new(point.x - half_size, point.y, point.z)
        end_point_z2 = Geom::Point3d.new(point.x + half_size, point.y, point.z)

        view.draw(GL_LINES, [start_point_z1, end_point_z1, start_point_z2, end_point_z2])
      end
    end

    def self.scale_to_specific_size
      model = Sketchup.active_model
      selection = model.selection
      return if selection.empty?

      first_entity = selection.first
      if first_entity.is_a?(Sketchup::Group) || first_entity.is_a?(Sketchup::ComponentInstance)
        bounds = first_entity.bounds
        default_width = bounds.width.to_mm.round
        default_height = bounds.height.to_mm.round
        default_depth = bounds.depth.to_mm.round
      else
        return
      end

      prompts = ["Ширина (X) в мм", "Глибина (Y) в мм", "Висота (Z) в мм"]
      defaults = [default_width, default_height, default_depth]
      input = UI.inputbox(prompts, defaults, "Введіть нові розміри об'єкта в міліметрах")
      return unless input

      new_width, new_height, new_depth = input.map { |i| i.to_f.mm }
      locked_sides = []

      model.start_operation('Scale to Specific Size', true)

      selection.each do |entity|
        next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

        dictionary = entity.attribute_dictionary("SU", false)
        lock_x = dictionary && dictionary["lock_x"] == true
        lock_y = dictionary && dictionary["lock_y"] == true
        lock_z = dictionary && dictionary["lock_z"] == true

        locked_sides.push('Ширина X') if lock_x
        locked_sides.push('Глибина Y') if lock_y
        locked_sides.push('Висота Z') if lock_z

        # Зберігаємо початкову позицію
        original_transformation = entity.transformation
        original_position = original_transformation.origin

        bounds = entity.bounds
        original_width = bounds.width
        original_height = bounds.height
        original_depth = bounds.depth

        scale_x = lock_x ? 1.0 : new_width / original_width
        scale_y = lock_y ? 1.0 : new_height / original_height
        scale_z = lock_z ? 1.0 : new_depth / original_depth

        # Масштабуємо відносно origin
        origin = entity.transformation.origin
        scale_transformation = Geom::Transformation.scaling(origin, scale_x, scale_y, scale_z)
        entity.transform!(scale_transformation)

        # Повертаємо об'єкт на початкову позицію
        current_position = entity.transformation.origin
        translation_vector = original_position - current_position
        translation = Geom::Transformation.translation(translation_vector)
        entity.transform!(translation)
      end

      model.commit_operation

      Sketchup.active_model.select_tool(LockPointsTool.new(first_entity)) unless locked_sides.empty?

      unless locked_sides.empty?
        UI.messagebox("Масштабування заборонено для сторін: #{locked_sides.join(', ')}")
      end
    end
  end

  # Додавання пункту до меню "Plugins"
  unless file_loaded?(__FILE__)
    menu = UI.menu('Plugins')
    menu.add_item('WWT_Масштабувати панель за розміром >>>') {
      LockPointsTool.scale_to_specific_size
    }
    file_loaded(__FILE__)
  end
end