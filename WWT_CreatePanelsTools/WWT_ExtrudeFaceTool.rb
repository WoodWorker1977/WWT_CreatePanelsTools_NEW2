require 'sketchup.rb'

module WWT_CreatePanelsTools
  module WWT_ExtrudeFaceTool
    
    def self.run_tool
      Sketchup.active_model.select_tool(ExtrudeFaceTool.new)
    end
    
    class ExtrudeFaceTool
      def initialize
        @model = Sketchup.active_model
        @view = @model.active_view
        @picked_face = nil
        @picked_entity = nil
        @screen_point = nil
        @full_transformation = nil
        
        # Змінні для роботи з атрибутами та матеріалами
        @wwt_attributes = {}
        @group_material = nil
        @selected_material = nil
        
        # Встановлюємо початкові значення за замовчуванням
        default_thickness = 18.0
        default_offset_left = 0.0
        default_offset_right = 0.0
        default_offset_bottom = 0.0
        default_offset_top = 0.0
        
        # Зчитуємо збережені значення
        @extrusion_thickness = Sketchup.read_default("CustomExtrudeTool", "thickness", default_thickness).to_f
        @offset_left = Sketchup.read_default("CustomExtrudeTool", "offset_left", default_offset_left).to_f
        @offset_right = Sketchup.read_default("CustomExtrudeTool", "offset_right", default_offset_right).to_f
        @offset_bottom = Sketchup.read_default("CustomExtrudeTool", "offset_bottom", default_offset_bottom).to_f
        @offset_top = Sketchup.read_default("CustomExtrudeTool", "offset_top", default_offset_top).to_f
        @selected_material = nil
        
        # Ініціалізуємо тимчасові змінні збереженими значеннями
        @temp_thickness = @extrusion_thickness
        @temp_material = ""
        @temp_offset_left = @offset_left
        @temp_offset_right = @offset_right
        @temp_offset_bottom = @offset_bottom
        @temp_offset_top = @offset_top
        
          # Не запускаємо діалог відразу, він буде запущений по ПКМ
        @dialog = nil
      end

      def reinitialize
        # Скидаємо до значень за замовчуванням
        @extrusion_thickness = 18.0
        @offset_left = 0.0
        @offset_right = 0.0
        @offset_bottom = 0.0
        @offset_top = 0.0
        @temp_thickness = @extrusion_thickness
        @temp_offset_left = @offset_left
        @temp_offset_right = @offset_right
        @temp_offset_bottom = @offset_bottom
        @temp_offset_top = @offset_top

        # Зберігаємо скинуті значення
        Sketchup.write_default("CustomExtrudeTool", "thickness", @extrusion_thickness)
        Sketchup.write_default("CustomExtrudeTool", "offset_left", @offset_left)
        Sketchup.write_default("CustomExtrudeTool", "offset_right", @offset_right)
        Sketchup.write_default("CustomExtrudeTool", "offset_bottom", @offset_bottom)
        Sketchup.write_default("CustomExtrudeTool", "offset_top", @offset_top)
        
        update_dialog_values if @dialog && @dialog.visible?
        @view.invalidate if @view
      end

      def activate
        if @dialog && !@dialog.visible?
          @dialog.show
          UI.start_timer(0.1, false) { update_dialog_values }
        elsif @dialog && @dialog.visible?
          @dialog.bring_to_front
          update_dialog_values
        end
        @view.invalidate
      end

      def deactivate(view)
        @dialog.close if @dialog && @dialog.visible?
      end

      # Додаємо новий метод getMenu для формування контекстного меню
      def getMenu(menu)
        menu.add_item("Налаштування екструзії") do
          # Якщо діалог ще не створено - створюємо його
          if @dialog.nil?
            setup_dialog
          end
          
          # Показуємо діалог
          if @dialog.visible?
            @dialog.bring_to_front
          else
            @dialog.show
          end
          
          # Оновлюємо значення в діалозі
          UI.start_timer(0.1, false) { update_dialog_values }
        end
        
        # Додаємо роздільник
        menu.add_separator
        
        # Додаємо інші пункти, якщо потрібно
        menu.add_item("Скинути налаштування") do
          reinitialize
          @view.invalidate if @view
        end
      end

      # Оновлюємо метод onRButtonDown для використання getMenu
      def onRButtonDown(flags, x, y, view)
        # Створюємо контекстне меню
        menu = UI::Menu.new
        
        # Заповнюємо меню через метод getMenu
        getMenu(menu)
        
        # Показуємо контекстне меню
        menu.popup(x, y)
        
        # Обов'язково повертаємо true, щоб SketchUp знав, що ми обробили подію
        true
      end

      # Обновленный метод setup_dialog с украинским названием и новым стилем
      def setup_dialog
        @dialog = UI::HtmlDialog.new({
          :dialog_title => "Налаштування екструзії",
          :preferences_key => "ExtrudeFaceTool",
          :scrollable => true,
          :resizable => true,
          :width => 300,
          :height => 350,
          :left => 200,
          :top => 200
        })

        html = <<-HTML
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="UTF-8">
            <style>
              html {
                height: 100%;
                overflow: hidden;
              }
              body {
                font-family: "Century Gothic", Arial, sans-serif;
                font-size: 12px;
                padding: 10px;
                background: #f5f5f5;
                margin: 0;
                height: 100%;
                overflow-y: auto;
              }
              .container {
                width: 100%;
              }
              .form-row {
                margin-bottom: 10px;
              }
              label {
                display: inline-block;
                width: 120px;
              }
              input[type="text"], input[type="number"], select {
                width: 90%;
                padding: 2px;
                border: 1px solid #e0e0e0;
                font-family: "Century Gothic", Arial, sans-serif;
                font-size: 12px;
              }
              select {
                width: 150px;
              }
              .checkbox-row {
                display: flex;
                align-items: center;
                margin-bottom: 15px;
              }
              .checkbox-row input[type="checkbox"] {
                margin-right: 5px;
              }
              .action-buttons {
                display: flex;
                justify-content: space-between;
                margin-top: 20px;
                position: sticky;
                bottom: 0;
                padding: 5px 0;
                background: #f5f5f5;
                z-index: 10;
              }
              button {
                padding: 3px 6px;
                cursor: pointer;
                background: #e0e0e0;
                color: #333;
                border: none;
                border-radius: 3px;
                font-size: 12px;
                font-family: "Century Gothic", Arial, sans-serif;
                transition: background 0.2s;
                margin-left: 10px;
              }
              button:hover {
                background: #d0d0d0;
              }
            </style>
          </head>
          <body>
            <div class="container">
              <form id="extrusionForm">
                <div class="form-row">
                  <label for="thickness">Товщина (мм):</label>
                  <input type="number" id="thickness" step="0.1" value="#{@extrusion_thickness}" style="width: 120px;">
                </div>
                
                <div class="form-row">
                  <label for="material">Матеріал:</label>
                  <select id="material" style="width: 150px;">
                    <option value="">За замовчуванням</option>
                    #{generate_material_options}
                  </select>
                </div>
          
                <div class="form-row">
                  <label for="offset_left">Відступ зліва (мм):</label>
                  <input type="number" id="offset_left" step="0.1" value="#{@offset_left}" style="width: 120px;">
                </div>
          
                <div class="form-row">
                  <label for="offset_right">Відступ справа (мм):</label>
                  <input type="number" id="offset_right" step="0.1" value="#{@offset_right}" style="width: 120px;">
                </div>
          
                <div class="form-row">
                  <label for="offset_bottom">Відступ знизу (мм):</label>
                  <input type="number" id="offset_bottom" step="0.1" value="#{@offset_bottom}" style="width: 120px;">
                </div>
          
                <div class="form-row">
                  <label for="offset_top">Відступ зверху (мм):</label>
                  <input type="number" id="offset_top" step="0.1" value="#{@offset_top}" style="width: 120px;">
                </div>
          
                <div class="action-buttons">
                  <button type="button" id="reset_button">Скинути</button>
                  <button type="button" id="apply_button">Застосувати</button>
                </div>
              </form>
            </div>
          
            <script>
              function getAndSendAllValues() {
                var thickness = document.getElementById('thickness').value;
                var material = document.getElementById('material').value;
                var offsetLeft = document.getElementById('offset_left').value;
                var offsetRight = document.getElementById('offset_right').value;
                var offsetBottom = document.getElementById('offset_bottom').value;
                var offsetTop = document.getElementById('offset_top').value;
                
                thickness = parseFloat(thickness) || 0;
                offsetLeft = parseFloat(offsetLeft) || 0;
                offsetRight = parseFloat(offsetRight) || 0;
                offsetBottom = parseFloat(offsetBottom) || 0;
                offsetTop = parseFloat(offsetTop) || 0;
                
                sketchup.updateSettings({
                  thickness: thickness,
                  material: material,
                  offset_left: offsetLeft,
                  offset_right: offsetRight,
                  offset_bottom: offsetBottom,
                  offset_top: offsetTop
                });
              }
              
              document.getElementById('thickness').addEventListener('input', getAndSendAllValues);
              document.getElementById('material').addEventListener('change', getAndSendAllValues);
              document.getElementById('offset_left').addEventListener('input', getAndSendAllValues);
              document.getElementById('offset_right').addEventListener('input', getAndSendAllValues);
              document.getElementById('offset_bottom').addEventListener('input', getAndSendAllValues);
              document.getElementById('offset_top').addEventListener('input', getAndSendAllValues);
              
              document.getElementById('apply_button').addEventListener('click', function() {
                getAndSendAllValues();
                sketchup.applySettings();
              });
              
              document.getElementById('reset_button').addEventListener('click', function() {
                sketchup.reinitialize();
              });
              
              window.onload = function() {
                setTimeout(getAndSendAllValues, 100);
              };
            </script>
          </body>
        </html>
        HTML

        @dialog.set_html(html)

        # Callback для оновлення всіх значень одночасно
        @dialog.add_action_callback("updateSettings") do |_, params|
          @temp_thickness = params["thickness"].to_f
          @temp_material = params["material"]
          @temp_offset_left = params["offset_left"].to_f
          @temp_offset_right = params["offset_right"].to_f
          @temp_offset_bottom = params["offset_bottom"].to_f
          @temp_offset_top = params["offset_top"].to_f
          @view.invalidate
        end

        # Callback для застосування налаштувань
        @dialog.add_action_callback("applySettings") do |_, _|
          @extrusion_thickness = @temp_thickness
          @selected_material = @model.materials[@temp_material] unless @temp_material.empty?
          @offset_left = @temp_offset_left
          @offset_right = @temp_offset_right
          @offset_bottom = @temp_offset_bottom
          @offset_top = @temp_offset_top

          Sketchup.write_default("CustomExtrudeTool", "thickness", @extrusion_thickness)
          Sketchup.write_default("CustomExtrudeTool", "offset_left", @offset_left)
          Sketchup.write_default("CustomExtrudeTool", "offset_right", @offset_right)
          Sketchup.write_default("CustomExtrudeTool", "offset_bottom", @offset_bottom)
          Sketchup.write_default("CustomExtrudeTool", "offset_top", @offset_top)

          @view.invalidate
        end

        @dialog.add_action_callback("reinitialize") { |_, _| reinitialize }
        
        # Устанавливаем позицию диалога
        @dialog.set_position(200, 200)
      end

      def update_dialog_values
        js_update = <<-JS
          document.getElementById('thickness').value = '#{@extrusion_thickness}';
          document.getElementById('offset_left').value = '#{@offset_left}';
          document.getElementById('offset_right').value = '#{@offset_right}';
          document.getElementById('offset_bottom').value = '#{@offset_bottom}';
          document.getElementById('offset_top').value = '#{@offset_top}';
          if (typeof getAndSendAllValues === 'function') {
            getAndSendAllValues();
          }
        JS
        @dialog.execute_script(js_update)
      end

      def generate_material_options
        materials = @model.materials
        materials.map { |mat| "<option value=\"#{mat.name}\">#{mat.name}</option>" }.join("\n")
      end

      def onMouseMove(flags, x, y, view)
        @screen_point = [x, y]
        ph = view.pick_helper
        ph.do_pick(x, y)
      
        @picked_entity = nil
        @picked_face = nil
        @full_transformation = Geom::Transformation.new
        @wwt_attributes = {}
        @group_material = nil
        @selected_material = nil
      
        pick_path = ph.path_at(0)
        if pick_path && pick_path.length > 0
          entity = nil
          face = nil
          transformation_stack = []
      
          # Збираємо всі трансформації у стеку
          pick_path.each do |element|
            if element.is_a?(Sketchup::Group) || element.is_a?(Sketchup::ComponentInstance)
              entity = element
              transformation_stack << element.transformation
            elsif element.is_a?(Sketchup::Face)
              face = element
              break
            end
          end
      
          if entity && face
            @picked_entity = entity
            @picked_face = face
            
            # Обчислюємо кумулятивну трансформацію вздовж шляху
            if transformation_stack.empty?
              @full_transformation = Geom::Transformation.new
            else
              @full_transformation = transformation_stack.reduce { |acc, trans| acc * trans }
            end
            
            # Аналізуємо матеріали та атрибути обраної групи
            analyze_group_materials(entity)
            
            # Убираем автоматический показ диалога
            # if @dialog && !@dialog.visible?
            #   @dialog.show
            #   UI.start_timer(0.2, false) { update_dialog_values }
            # end
          end
        end
      
        view.invalidate
      end

      # Аналізує матеріали групи для подальшого використання
      def analyze_group_materials(group)
        return unless group
        @group_material = group.material
        entities = group.is_a?(Sketchup::ComponentInstance) ? group.definition.entities : group.entities
        faces = entities.grep(Sketchup::Face)
        sorted_faces = faces.sort_by { |face| -face.area }
        smaller_faces = sorted_faces[2..-1] || []
        smallest_face_with_material = smaller_faces.find { |face| face.material }
        @selected_material = smallest_face_with_material.material if smallest_face_with_material

        if dict = group.attribute_dictionary('WWT')
          dict.each_pair { |key, value| @wwt_attributes[key] = value }
        end

        faces.each do |face|
          if face_dict = face.attribute_dictionary('WWT')
            if face_dict['sidedness_type'] == 'Single_sided'
              @wwt_attributes['single_sided_material'] = face.material
              @wwt_attributes['has_single_sided'] = true
            end
          end
        end
      end

      # Застосовує матеріали та атрибути до групи
      def apply_materials_and_attributes(group, custom_material = nil)
        return unless group
        
        if @wwt_attributes && !@wwt_attributes.empty?
          dict = group.attribute_dictionary('WWT', true)
          @wwt_attributes.each do |key, value|
            next if ['userStyle', 'Normal', 'is_panel_face'].include?(key)
            dict[key] = value
          end
        end

        faces = group.entities.grep(Sketchup::Face)
        faces.each { |face| face.set_attribute('WWT', 'is_panel_face', true) }
        largest_faces = faces.sort_by { |face| -face.area }.first(2)
        
        largest_faces.each do |face|
          face.material = nil
          face.delete_attribute('WWT', 'sidedness_type')
        end

        material_to_apply = custom_material || @selected_material
        remaining_faces = faces - largest_faces
        remaining_faces.each { |face| face.material = material_to_apply if material_to_apply }

        material_name = @temp_material.empty? ? '' : @temp_material
        dialog_material = material_name.empty? ? nil : @model.materials[material_name]
        
        # Встановлюємо матеріал групи: 
        # 1. Матеріал вибраний у діалозі (якщо є)
        # 2. Інакше матеріал з оригінальної групи
        # 3. Інакше матеріал переданий як параметр
        group.material = dialog_material || @group_material || custom_material
      end

      def draw(view)
        if @picked_face && @full_transformation
          # Функція для перевірки близькості точок
          close_enough = lambda { |pt1, pt2, tolerance = 0.001| pt1.distance(pt2) < tolerance }
          
          length_unit = @model.options["UnitsOptions"]["LengthUnit"]
          to_inches = lambda { |mm| 
            return 0.0 if mm.nil? || !mm.is_a?(Numeric)
            case length_unit
            when 0 then mm / 25.4
            when 1 then mm / 10.0
            when 2 then mm / 25.4
            when 3 then mm / 1000.0 / 25.4
            when 4 then mm / 12.0 / 25.4
            else mm / 25.4
            end.to_f
          }
      
          extrusion_height = to_inches.call(@temp_thickness)
          offset_left = to_inches.call(@temp_offset_left)
          offset_right = to_inches.call(@temp_offset_right)
          offset_bottom = to_inches.call(@temp_offset_bottom)
          offset_top = to_inches.call(@temp_offset_top)
      
          # Отримуємо нормаль грані
          face_normal = @picked_face.normal.clone
          
          # Якщо нормаль не дійсна, обчислюємо її
          if !face_normal.valid? || face_normal.length.zero?
            outer_loop = @picked_face.outer_loop
            if outer_loop && outer_loop.vertices.length >= 3
              pts = outer_loop.vertices.map { |v| v.position }
              edge1 = pts[1].vector_to(pts[0])
              edge2 = pts[2].vector_to(pts[1])
              face_normal = edge1.cross(edge2)
              face_normal = Geom::Vector3d.new(0, 0, 1) unless face_normal.valid? && face_normal.length > 0
              face_normal.normalize!
            else
              face_normal = Geom::Vector3d.new(0, 0, 1)
            end
          end
      
          # Створюємо вектор екструзії
          extrusion_vector = face_normal.clone
          extrusion_vector.length = extrusion_height
      
          # Отримуємо всі контури грані
          all_loops = @picked_face.loops
          
          # Визначаємо локальні осі U і V для грані на основі першого контуру
          first_loop_points = all_loops.first.vertices.map { |v| v.position }
          u_axis, v_axis = get_face_axes(first_loop_points, face_normal)
          
          # Знаходимо глобальні min/max для всіх контурів для обчислення офсетів
          all_points = []
          all_loops.each do |loop|
            all_points.concat(loop.vertices.map { |v| v.position })
          end
          
          # Обчислюємо проекції в локальних координатах для всіх точок
          u_projections = all_points.map { |pt| u_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
          v_projections = all_points.map { |pt| v_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
          min_u = u_projections.min
          max_u = u_projections.max
          min_v = v_projections.min
          max_v = v_projections.max
      
          # Створюємо вектори офсетів у локальних координатах
          left_offset_vector = u_axis.clone
          left_offset_vector.length = offset_left
          right_offset_vector = u_axis.clone
          right_offset_vector.length = offset_right
          right_offset_vector.reverse!
          bottom_offset_vector = v_axis.clone
          bottom_offset_vector.length = offset_bottom
          top_offset_vector = v_axis.clone
          top_offset_vector.length = offset_top
          top_offset_vector.reverse!
          
          # Для відображення - змінено колір на помаранчевий
          view.drawing_color = Sketchup::Color.new(255, 120, 0, 255)
          view.line_stipple = ""
          view.line_width = 2
          
          # Малюємо кожен контур окремо
          all_loops.each do |loop|
            base_points = loop.vertices.map { |v| v.position }
            
            # Застосовуємо офсети в локальних координатах для цього контуру
            loop_u_projections = base_points.map { |pt| u_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
            loop_v_projections = base_points.map { |pt| v_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
            
            offset_points = base_points.map.with_index do |pt, i|
              new_pt = pt.clone
              u_proj = loop_u_projections[i]
              v_proj = loop_v_projections[i]
              
              new_pt = new_pt.offset(left_offset_vector) if (u_proj - min_u).abs < 0.001 && offset_left != 0
              new_pt = new_pt.offset(right_offset_vector) if (u_proj - max_u).abs < 0.001 && offset_right != 0
              new_pt = new_pt.offset(bottom_offset_vector) if (v_proj - min_v).abs < 0.001 && offset_bottom != 0
              new_pt = new_pt.offset(top_offset_vector) if (v_proj - max_v).abs < 0.001 && offset_top != 0
              new_pt
            end
            
            # Перевіряємо на дублікати в контурі
            has_duplicates = offset_points.each_cons(2).any? { |pt1, pt2| close_enough.call(pt1, pt2) }
            unless has_duplicates
              # Створюємо верхні точки
              top_points = offset_points.map { |pt| pt.offset(extrusion_vector) }
              
              # Трансформуємо точки в глобальний простір для прев'ю
              global_offset_points = offset_points.map { |pt| pt.transform(@full_transformation) }
              global_top_points = top_points.map { |pt| pt.transform(@full_transformation) }
              
              # Малюємо нижній контур
              view.draw(GL_LINE_LOOP, global_offset_points)
              
              # Малюємо верхній контур
              view.draw(GL_LINE_LOOP, global_top_points)
              
              # Малюємо лінії між контурами
              global_offset_points.each_with_index { |pt, i| view.draw(GL_LINES, [pt, global_top_points[i]]) }
            end
          end
        end
      end

      # Допоміжна функція для отримання осей грані
      def get_face_axes(points, normal)
        u_axis = points[0].vector_to(points[1])
        if u_axis.valid? && u_axis.length > 0
          u_axis.normalize!
          v_axis = normal.cross(u_axis)
          if !v_axis.valid? || v_axis.length.zero?
            v_axis = Geom::Vector3d.new(0, 0, 1).cross(u_axis)
            v_axis = Geom::Vector3d.new(0, 1, 0) unless v_axis.valid? && v_axis.length > 0
          end
          v_axis.normalize!
        else
          u_axis = Geom::Vector3d.new(1, 0, 0)
          v_axis = Geom::Vector3d.new(0, 1, 0)
        end
        return u_axis, v_axis
      end

      def onLButtonDown(flags, x, y, view)
        return unless @picked_entity && @picked_face && @full_transformation

        @model.start_operation("Create Parallelepiped with Offset", true)

        length_unit = @model.options["UnitsOptions"]["LengthUnit"]
        to_inches = lambda { |mm| 
          return 0.0 if mm.nil? || !mm.is_a?(Numeric)
          case length_unit
          when 0 then mm / 25.4
          when 1 then mm / 10.0
          when 2 then mm / 25.4
          when 3 then mm / 1000.0 / 25.4
          when 4 then mm / 12.0 / 25.4
          else mm / 25.4
          end.to_f
        }

        # Функція для перевірки близькості точок
        close_enough = lambda { |pt1, pt2, tolerance = 0.001| pt1.distance(pt2) < tolerance }

        # Використовуємо тимчасові значення для створення об'єкта
        extrusion_height = to_inches.call(@temp_thickness)
        offset_left = to_inches.call(@temp_offset_left)
        offset_right = to_inches.call(@temp_offset_right)
        offset_bottom = to_inches.call(@temp_offset_bottom)
        offset_top = to_inches.call(@temp_offset_top)

        entities = @model.active_entities
        
        # Отримуємо нормаль грані у локальних координатах
        face_normal = @picked_face.normal.clone
        
        # Якщо нормаль не дійсна, обчислюємо її на основі першого контуру
        if !face_normal.valid? || face_normal.length.zero?
          outer_loop = @picked_face.outer_loop
          if outer_loop && outer_loop.vertices.length >= 3
            pts = outer_loop.vertices.map { |v| v.position }
            edge1 = pts[1].vector_to(pts[0])
            edge2 = pts[2].vector_to(pts[1])
            face_normal = edge1.cross(edge2)
            face_normal = Geom::Vector3d.new(0, 0, 1) unless face_normal.valid? && face_normal.length > 0
            face_normal.normalize!
          else
            face_normal = Geom::Vector3d.new(0, 0, 1)
          end
        end

        # Створюємо вектор екструзії у локальних координатах
        extrusion_vector = face_normal.clone
        extrusion_vector.length = extrusion_height

        # Створюємо групу
        group = entities.add_group
        group.name = "Панель_" + Time.now.strftime("%Y%m%d%H%M%S") # Даємо унікальну назву групі
        group_entities = group.entities

        # Обробляємо всі контури грані окремо
        all_loops = @picked_face.loops
        
        # Визначаємо локальні осі U і V для грані на основі першого контуру
        first_loop_points = all_loops.first.vertices.map { |v| v.position }
        u_axis, v_axis = get_face_axes(first_loop_points, face_normal)
        
        # Знаходимо глобальні min/max для всіх контурів для обчислення офсетів
        all_points = []
        all_loops.each do |loop|
          all_points.concat(loop.vertices.map { |v| v.position })
        end
        
        # Обчислюємо проекції в локальних координатах для всіх точок
        u_projections = all_points.map { |pt| u_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
        v_projections = all_points.map { |pt| v_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
        min_u = u_projections.min
        max_u = u_projections.max
        min_v = v_projections.min
        max_v = v_projections.max

        # Створюємо вектори офсетів у локальних координатах
        left_offset_vector = u_axis.clone
        left_offset_vector.length = offset_left
        right_offset_vector = u_axis.clone
        right_offset_vector.length = offset_right
        right_offset_vector.reverse!
        bottom_offset_vector = v_axis.clone
        bottom_offset_vector.length = offset_bottom
        top_offset_vector = v_axis.clone
        top_offset_vector.length = offset_top
        top_offset_vector.reverse!

        # Масиви для зберігання зміщених контурів
        offset_loops = []
        top_loops = []
        
        # Обробляємо кожен контур окремо
        all_loops.each_with_index do |loop, loop_index|
          # Отримуємо локальні координати вершин контуру
          base_points = loop.vertices.map { |v| v.position }
          
          # Застосовуємо офсети в локальних координатах для цього контуру
          loop_u_projections = base_points.map { |pt| u_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
          loop_v_projections = base_points.map { |pt| v_axis.dot(pt.vector_to(Geom::Point3d.new(0,0,0))) }
          
          offset_points = base_points.map.with_index do |pt, i|
            new_pt = pt.clone
            u_proj = loop_u_projections[i]
            v_proj = loop_v_projections[i]
            
            new_pt = new_pt.offset(left_offset_vector) if (u_proj - min_u).abs < 0.001 && offset_left != 0
            new_pt = new_pt.offset(right_offset_vector) if (u_proj - max_u).abs < 0.001 && offset_right != 0
            new_pt = new_pt.offset(bottom_offset_vector) if (v_proj - min_v).abs < 0.001 && offset_bottom != 0
            new_pt = new_pt.offset(top_offset_vector) if (v_proj - max_v).abs < 0.001 && offset_top != 0
            new_pt
          end
          
          # Перевіряємо на дублікати в контурі
          has_duplicates = offset_points.each_cons(2).any? { |pt1, pt2| close_enough.call(pt1, pt2) }
          if has_duplicates
            # Пропускаємо цей контур, якщо є дублікати
            next
          end
          
          # Створюємо верхні точки для контуру
          top_points = offset_points.map { |pt| pt.offset(extrusion_vector) }
          
          offset_loops << offset_points
          top_loops << top_points
        end
        
        # Перевіряємо, чи залишилися контури після перевірки на дублікати
        if offset_loops.empty?
          @model.abort_operation
          return
        end
        
        # Знаходимо мінімальну точку для всіх контурів
        all_offset_and_top_points = offset_loops.flatten + top_loops.flatten
        min_point = find_min_point(all_offset_and_top_points, u_axis, v_axis, face_normal)
        origin_point = Geom::Point3d.new(0, 0, 0)
        translation_vector = min_point.vector_to(origin_point)
        
        # Масиви для зберігання зміщених та транслюованих точок
        translated_offset_loops = []
        translated_top_loops = []
        
        # Зсуваємо всі точки, щоб origin був у нижньому лівому куті
        offset_loops.each_with_index do |loop_points, index|
          translated_offset_loops << loop_points.map { |pt| pt.offset(translation_vector) }
          translated_top_loops << top_loops[index].map { |pt| pt.offset(translation_vector) }
        end
        
        # Створюємо нижню грань з усіма контурами
        if translated_offset_loops.length > 0
          # Створюємо зовнішній контур
          outer_loop_points = translated_offset_loops[0]
          bottom_face = group_entities.add_face(outer_loop_points)
          
          # Перевіряємо орієнтацію
          if bottom_face.normal.dot(face_normal) > 0
            bottom_face.reverse!
          end
          
          # Додаємо внутрішні контури для нижньої грані
          (1...translated_offset_loops.length).each do |i|
            inner_loop_points = translated_offset_loops[i]
            # Додаємо внутрішній контур
            inner_face = group_entities.add_face(inner_loop_points)
            # Переконуємося, що контур має правильну орієнтацію для отвору
            if inner_face.normal.dot(face_normal) < 0
              inner_face.reverse!
            end
            # Видаляємо зайву грань, щоб залишити лише отвір
            inner_face.erase! if inner_face.valid?
          end
          
          # Створюємо верхню грань з усіма контурами
          outer_top_points = translated_top_loops[0]
          top_face = group_entities.add_face(outer_top_points)
          
          # Перевіряємо орієнтацію
          if top_face.normal.dot(face_normal) < 0
            top_face.reverse!
          end
          
          # Додаємо внутрішні контури для верхньої грані
          (1...translated_top_loops.length).each do |i|
            inner_top_points = translated_top_loops[i]
            # Додаємо внутрішній контур
            inner_top_face = group_entities.add_face(inner_top_points)
            # Переконуємося, що контур має правильну орієнтацію для отвору
            if inner_top_face.normal.dot(face_normal) > 0
              inner_top_face.reverse!
            end
            # Видаляємо зайву грань, щоб залишити лише отвір
            inner_top_face.erase! if inner_top_face.valid?
          end
          
          # Створюємо бічні грані для кожного контуру
          translated_offset_loops.each_with_index do |loop_points, loop_index|
            top_loop_points = translated_top_loops[loop_index]
            
            # Для кожного ребра контуру створюємо бічну грань
            (0...loop_points.length).each do |i|
              next_i = (i + 1) % loop_points.length
              side_points = [
                loop_points[i], 
                loop_points[next_i], 
                top_loop_points[next_i], 
                top_loop_points[i]
              ]
              
              # Перевіряємо на дублікати
              has_side_duplicates = side_points.combination(2).any? { |pt1, pt2| close_enough.call(pt1, pt2) }
              unless has_side_duplicates
                side_face = group_entities.add_face(side_points)
                # Забезпечуємо правильну орієнтацію бічної грані
                # Для зовнішнього контуру нормаль має бути назовні, для внутрішніх - всередину
                normal_should_be_outward = (loop_index == 0)
                edge_vector = loop_points[i].vector_to(loop_points[next_i])
                expected_normal = edge_vector.cross(extrusion_vector)
                expected_normal.reverse! unless normal_should_be_outward
                
                if side_face.normal.dot(expected_normal) < 0
                  side_face.reverse!
                end
              end
            end
          end
        end
        
        # Застосовуємо матеріали та атрибути до створеної групи
        apply_materials_and_attributes(group)
        
        # Створюємо трансформації і застосовуємо до групи
        group.transformation = @full_transformation * Geom::Transformation.translation(min_point)
        
        # Оновлюємо постійні змінні та зберігаємо їх
        @extrusion_thickness = @temp_thickness
        @offset_left = @temp_offset_left
        @offset_right = @temp_offset_right
        @offset_bottom = @temp_offset_bottom
        @offset_top = @temp_offset_top
        
        Sketchup.write_default("CustomExtrudeTool", "thickness", @extrusion_thickness)
        Sketchup.write_default("CustomExtrudeTool", "offset_left", @offset_left)
        Sketchup.write_default("CustomExtrudeTool", "offset_right", @offset_right)
        Sketchup.write_default("CustomExtrudeTool", "offset_bottom", @offset_bottom)
        Sketchup.write_default("CustomExtrudeTool", "offset_top", @offset_top)
        
        @model.commit_operation
        view.invalidate
      rescue => e
        puts "Error: #{e.message}"
        puts e.backtrace.join("\n")
        @model.abort_operation
      ensure
        view.invalidate
      end

      # Допоміжний метод для знаходження нижнього лівого кута
      def find_min_point(points, u_axis, v_axis, normal)
        # Проектуємо всі точки на локальні осі
        origin = Geom::Point3d.new(0, 0, 0)
        
        # Знаходимо мінімальні та максимальні проекції
        u_projs = points.map { |pt| u_axis.dot(pt.vector_to(origin)) }
        v_projs = points.map { |pt| v_axis.dot(pt.vector_to(origin)) }
        n_projs = points.map { |pt| normal.dot(pt.vector_to(origin)) }
        
        min_u = u_projs.min
        max_u = u_projs.max
        min_v = v_projs.min
        max_v = v_projs.max
        min_n = n_projs.min
        max_n = n_projs.max
        
        # Шукаємо точку, яка має мінімальну проекцію по осі u та v
        # та мінімальну проекцію по нормалі
        min_point = nil
        min_distance = Float::INFINITY
        
        points.each do |pt|
          u_proj = u_axis.dot(pt.vector_to(origin))
          v_proj = v_axis.dot(pt.vector_to(origin))
          n_proj = normal.dot(pt.vector_to(origin))
          
          # Знаходимо відстань до точки з мінімальними координатами
          distance = (u_proj - min_u)**2 + (v_proj - min_v)**2 + (n_proj - min_n)**2
          
          if distance < min_distance
            min_distance = distance
            min_point = pt
          end
        end
        
        return min_point || points.first
      end

      # Копіює текстурне відображення з однієї грані на іншу
      def copy_texture_mapping(source_face, target_face)
        return unless source_face && target_face
        
        # Намагаємося скопіювати матеріал
        material = source_face.material || source_face.back_material
        if material
          target_face.material = material
        end
        
        # Намагаємося скопіювати атрибути
        source_dict = source_face.attribute_dictionary('WWT')
        if source_dict
          target_dict = target_face.attribute_dictionary('WWT', true)
          source_dict.each_pair do |key, value|
            target_dict[key] = value
          end
        end
      end
    end
  end
end

# Запуск інструменту, якщо файл запускається безпосередньо
if __FILE__ == $0
  Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_ExtrudeFaceTool::ExtrudeFaceTool.new)
end