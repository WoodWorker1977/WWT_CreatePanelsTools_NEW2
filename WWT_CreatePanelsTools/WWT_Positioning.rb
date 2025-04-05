require 'sketchup.rb'

module WWT_Positioning
  class CubeMove
    def initialize(model, direction, distance = 0)
      @model = model
      @entities = model.active_entities
      @selection = model.selection
      set_direction(direction)
      @distance = distance
    end

    def move_selected_groups
      start_operation('Переміщення панелей')
      selected_groups = @selection.grep(Sketchup::Group)

      if selected_groups.empty?
        UI.messagebox("Немає вибраних груп для переміщення.")
        abort_operation
        return
      end

      selected_groups.each do |selected_group|
        move_group_to_adjacent(selected_group)
      end

      commit_operation
    end

    private

    def set_direction(direction)
      @move_left = @move_right = @move_top = @move_dn = @move_front = @move_behind = false

      case direction
      when :move_left
        @move_left = true
      when :move_right
        @move_right = true
      when :move_top
        @move_top = true
      when :move_dn
        @move_dn = true
      when :move_front
        @move_front = true
      when :move_behind
        @move_behind = true
      end
    end

    def move_group_to_adjacent(selected_group)
      move_distance_x = 0
      move_distance_y = 0
      move_distance_z = 0

      if @distance == 0
        left_group, right_group, top_group, dn_group, front_group, behind_group = find_adjacent_groups(selected_group)

        if @move_left && left_group
          move_distance_x = left_group.bounds.max.x - selected_group.bounds.min.x
        elsif @move_right && right_group
          move_distance_x = right_group.bounds.min.x - selected_group.bounds.max.x
        end

        if @move_front && front_group
          move_distance_y = front_group.bounds.min.y - selected_group.bounds.max.y
        elsif @move_behind && behind_group
          move_distance_y = behind_group.bounds.max.y - selected_group.bounds.min.y
        end

        if @move_top && top_group
          move_distance_z = top_group.bounds.min.z - selected_group.bounds.max.z
        elsif @move_dn && dn_group
          move_distance_z = dn_group.bounds.max.z - selected_group.bounds.min.z
        end
      else
        move_distance_x = -@distance if @move_left
        move_distance_x = @distance if @move_right
        move_distance_y = -@distance if @move_front
        move_distance_y = @distance if @move_behind
        move_distance_z = @distance if @move_top
        move_distance_z = -@distance if @move_dn
      end

      if move_distance_x != 0 || move_distance_y != 0 || move_distance_z != 0
        move_transform = Geom::Transformation.new([move_distance_x, move_distance_y, move_distance_z])
        selected_group.transform!(move_transform)
      end
    end

    def find_adjacent_groups(selected_group)
      left_group = right_group = top_group = dn_group = front_group = behind_group = nil
      min_left_gap = min_right_gap = min_top_gap = min_dn_gap = min_front_gap = min_behind_gap = Float::INFINITY
      selected_bounds = selected_group.bounds

      @entities.grep(Sketchup::Group).each do |group|
        next if group == selected_group

        if within_bounds_yz?(selected_bounds, group.bounds)
          left_group, min_left_gap = update_closest_group(left_group, group, selected_bounds.min.x - group.bounds.max.x, min_left_gap)
          right_group, min_right_gap = update_closest_group(right_group, group, group.bounds.min.x - selected_bounds.max.x, min_right_gap)
        end
        if within_bounds_xz?(selected_bounds, group.bounds)
          front_group, min_front_gap = update_closest_group(front_group, group, group.bounds.min.y - selected_bounds.max.y, min_front_gap)
          behind_group, min_behind_gap = update_closest_group(behind_group, group, selected_bounds.min.y - group.bounds.max.y, min_behind_gap)
        end
        if within_bounds_xy?(selected_bounds, group.bounds)
          top_group, min_top_gap = update_closest_group(top_group, group, group.bounds.min.z - selected_bounds.max.z, min_top_gap)
          dn_group, min_dn_gap = update_closest_group(dn_group, group, selected_bounds.min.z - group.bounds.max.z, min_dn_gap)
        end
      end

      [left_group, right_group, top_group, dn_group, front_group, behind_group]
    end

    def within_bounds_yz?(selected_bounds, group_bounds)
      (group_bounds.min.y <= selected_bounds.max.y && group_bounds.max.y >= selected_bounds.min.y) &&
      (group_bounds.min.z <= selected_bounds.max.z && group_bounds.max.z >= selected_bounds.min.z)
    end

    def within_bounds_xz?(selected_bounds, group_bounds)
      (group_bounds.min.x <= selected_bounds.max.x && group_bounds.max.x >= selected_bounds.min.x) &&
      (group_bounds.min.z <= selected_bounds.max.z && group_bounds.max.z >= selected_bounds.min.z)
    end

    def within_bounds_xy?(selected_bounds, group_bounds)
      (group_bounds.min.x <= selected_bounds.max.x && group_bounds.max.x >= selected_bounds.min.x) &&
      (group_bounds.min.y <= selected_bounds.max.y && group_bounds.max.y >= selected_bounds.min.y)
    end

    def update_closest_group(current_group, new_group, gap, min_gap)
      if gap > 0 && gap < min_gap
        [new_group, gap]
      else
        [current_group, min_gap]
      end
    end

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

  class CubeMoveTool
    MM_TO_INCH = 0.0393701

    def initialize(direction)
      @direction = direction
      @distance = 0
    end

    def activate
      Sketchup::set_status_text("Введіть відстань для переміщення та натисніть Enter", SB_VCB_LABEL)
      Sketchup::set_status_text(@distance.to_s, SB_VCB_VALUE)
    end

    def onUserText(text, view)
      distance_mm = text.to_f
      if distance_mm != 0
        @distance = distance_mm * MM_TO_INCH
        CubeMove.new(Sketchup.active_model, @direction, @distance).move_selected_groups
      else
        UI.messagebox("Некоректне значення. Введіть число більше нуля.")
      end
    end

    def onReturn(view)
      CubeMove.new(Sketchup.active_model, @direction, 0).move_selected_groups
    end
  end

  module CubeMoveMenu
    SETTINGS_KEY = "CubeMove_Settings"
    MM_TO_INCH = 0.0393701

    def self.add_extension_submenu
      main_menu = UI.menu("Extensions")
      arrange_submenu = main_menu.add_submenu('WWT_Розташувати об\'єкти >>>')
      add_arrange_submenu_items(arrange_submenu)
    end

    def self.add_arrange_submenu_items(submenu)
      submenu.add_item('- ліворуч') { activate_tool(:move_left) }
      submenu.add_item('- праворуч') { activate_tool(:move_right) }
      submenu.add_item('- вгору') { activate_tool(:move_top) }
      submenu.add_item('- вниз') { activate_tool(:move_dn) }
      submenu.add_item('- позаду') { activate_tool(:move_front) }
      submenu.add_item('- по переду') { activate_tool(:move_behind) }
    end

    def self.activate_tool(direction)
      Sketchup.active_model.select_tool(CubeMoveTool.new(direction))
    end
  end

  CubeMoveMenu.add_extension_submenu
end
