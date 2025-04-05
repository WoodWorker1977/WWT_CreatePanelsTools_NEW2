require 'sketchup.rb'
require 'extensions.rb'
require 'json'

module WWT_CreatePanelsTools
  module WWT_CreatePanelArray
    def self.run_tool
      Sketchup.active_model.select_tool(CubTool.new)
    end

    def self.reload_tool
      if Sketchup.active_model && Sketchup.active_model.respond_to?(:tools)
        current_tool = Sketchup.active_model.tools.active_tool
        if current_tool.is_a?(CubTool)
          Sketchup.active_model.select_tool(nil)
        end
        Sketchup.active_model.select_tool(CubTool.new)
      end
    end

# Функція для перевірки чи збережена модель з двомовним повідомленням
def self.check_model_saved(model)
  unless model.path
    message = "Для збереження налаштувань потрібно спочатку зберегти модель.\n\n" +
              "To save settings, you need to save the model first."
    UI.messagebox(message)
    return false
  end
  true
end

# Метод для збереження положення діалогу
def self.save_dialog_position(model, dialog_type, left, top)
  # Перевіряємо чи збережена модель
  return unless check_model_saved(model)
  
  dict = model.attribute_dictionary("WWT_CreatePanelArray_Settings", true)
  dict["#{dialog_type}_dialog_left"] = left
  dict["#{dialog_type}_dialog_top"] = top
  
  # Зберігаємо модель для гарантованого збереження налаштувань
  model.save if model.path
end

# Метод для збереження розмірів діалогу
def self.save_dialog_size(model, dialog_type, width, height)
  # Перевіряємо чи збережена модель
  return unless check_model_saved(model)
  
  dict = model.attribute_dictionary("WWT_CreatePanelArray_Settings", true)
  dict["#{dialog_type}_dialog_width"] = width
  dict["#{dialog_type}_dialog_height"] = height
  
  # Зберігаємо модель для гарантованого збереження налаштувань
  model.save if model.path
end

    class CubTool
      public

# Оновлений метод initialize для ініціалізації напрямкових зсувів
def initialize
  @num_panels = 3 # Початкове значення кількості панелей
  @offset = 0.mm  # Початковий загальний зсув
  
  # Окремі зсуви для кожного боку
  @offset_left = 0.mm    # Лівий зсув
  @offset_right = 0.mm   # Правий зсув
  @offset_top = 0.mm     # Верхній зсув
  @offset_bottom = 0.mm  # Нижній зсув
  
  reset_tool_state
  @hidden_abf_groups = []
  @ctrl_pressed = false
  @view = nil
  @saved_settings = load_saved_settings(Sketchup.active_model)
  
  # Початкове значення імені за замовчуванням
  @base_name = @saved_settings[:base_name] || "Панель"
  
  # Завантажуємо зсуви, якщо вони вже були встановлені
  @offset = @saved_settings[:offset].to_f.mm if @saved_settings[:offset]
  @offset_left = @saved_settings[:offset_left].to_f.mm if @saved_settings[:offset_left]
  @offset_right = @saved_settings[:offset_right].to_f.mm if @saved_settings[:offset_right]
  @offset_top = @saved_settings[:offset_top].to_f.mm if @saved_settings[:offset_top]
  @offset_bottom = @saved_settings[:offset_bottom].to_f.mm if @saved_settings[:offset_bottom]
end

def activate
  reset_tool_state
  hide_abf_groups
  @view = Sketchup.active_model.active_view
  @saved_settings = load_saved_settings(Sketchup.active_model)
  # Оновлюємо базове ім'я при активації інструменту
  @base_name = @saved_settings[:base_name] || "Панель"
  @num_panels = 3
  
  # Завантажуємо окремі офсети
  @offset_left = @saved_settings[:offset_left].to_f.mm if @saved_settings[:offset_left]
  @offset_right = @saved_settings[:offset_right].to_f.mm if @saved_settings[:offset_right]
  @offset_top = @saved_settings[:offset_top].to_f.mm if @saved_settings[:offset_top]
  @offset_bottom = @saved_settings[:offset_bottom].to_f.mm if @saved_settings[:offset_bottom]
  
  # Змінюємо підказку залежно від режиму
  if @ctrl_pressed
    # При активації в режимі зсуву відразу встановлюємо зсув на 0
    @offset = 0.mm
    save_offset_setting(Sketchup.active_model, "offset", "0")
    
    Sketchup.vcb_label = "Зсув панелей (мм)"
    UI.start_timer(0.1) { Sketchup.vcb_value = "#{@offset.to_mm}" }
  else
    # В режимі кількості панелей можна зберігати попереднє значення зсуву
    @offset = @saved_settings[:offset].to_f.mm if @saved_settings[:offset]
    
    Sketchup.vcb_label = "Кількість панелей"
    UI.start_timer(0.1) { Sketchup.vcb_value = "#{@num_panels}" }
  end
end

      def deactivate(view)
        # Закриваємо всі відкриті діалоги
        close_all_dialogs
        # Показуємо приховані групи
        show_abf_groups
        # Скидаємо стан інструменту
        reset_tool_state
        # Оновлюємо вид
        view.invalidate
      end

      # Метод для закриття всіх діалогів
      def close_all_dialogs
        # Закриття базового діалогу
        if @basic_dialog && @basic_dialog.respond_to?(:visible?) && @basic_dialog.visible?
          @basic_dialog.close
          @basic_dialog = nil
        end
      end

      def resume(view)
        view.invalidate
      end

def onKeyDown(key, repeat, flags, view)
  if key == 17 # код клавіші Ctrl
    @ctrl_pressed = !@ctrl_pressed
    if @ctrl_pressed
      Sketchup.status_text = "Режим зміщення панелей увімкнено"
      Sketchup.vcb_label = "Зсув панелей (мм)"
      
      # Відразу встановлюємо зміщення на 0 і оновлюємо превью
      @offset = 0.mm
      
      # Зберігаємо значення в налаштуваннях
      save_offset_setting(Sketchup.active_model, "offset", "0")
      
      # Оновлюємо VCB
      UI.start_timer(0) { Sketchup.vcb_value = @offset.to_mm.to_s }
    else
      Sketchup.status_text = "Режим вибору кількості панелей увімкнено"
      Sketchup.vcb_label = "Кількість панелей"
      UI.start_timer(0) { Sketchup.vcb_value = @num_panels.to_s }
    end
    view.invalidate
    return true
  end
  false
end

      def onKeyUp(key, repeat, flags, view)
        false
      end

      def onUserText(text, view)
        if @ctrl_pressed
          # Для режиму зміщення обробляємо зсув
          begin
            value = text.to_f.mm
            @offset = value
            save_offset_setting(Sketchup.active_model, "offset", value.to_mm.to_s)
            UI.start_timer(0) { Sketchup.vcb_value = value.to_mm.to_s; view.invalidate }
            true
          rescue
            UI.messagebox("Невірний формат числа")
            UI.start_timer(0) { Sketchup.vcb_value = @offset.to_mm.to_s }
            false
          end
        else
          # Для режиму кількості панелей
          value = text.to_i
          if value > 0
            @num_panels = value
            UI.start_timer(0) { Sketchup.vcb_value = @num_panels.to_s; view.invalidate }
            true
          else
            UI.messagebox("Введіть додатнє ціле число")
            UI.start_timer(0) { Sketchup.vcb_value = @num_panels.to_s }
            false
          end
        end
      end
      
      def onRButtonDown(flags, x, y, view)
        @view = view
        return false if flags & CONSTRAINTKEYS_SHIFT != 0
        menu = UI::Menu.new
        getMenu(menu)
        menu.popup(x, y) unless menu.instance_variable_get(:@items).empty?
        true
      end

      # Оновлений метод getMenu для пунктів контекстного меню
      def getMenu(menu)
        menu.add_item("Налаштування масиву панелей") do
          if valid_preview_state?
            vectors = calculate_preview_vectors
            if vectors
              points = create_preview_rectangle(vectors)
              if points
                adapt_rectangle(points, @center_point, vectors[:right], vectors[:up], @view)
                extrusion_length = find_safe_extrusion_length(points[0], @face_normal, @view)
                if extrusion_length && extrusion_length > 0
                  @preview_data = { points: points, extrusion_length: extrusion_length, transformation: @full_transform, normal: @face_normal }
                  @original_extrusion_vector = @face_normal.clone
                end
              end
            end
          end
          # Виклик діалогу налаштувань
          show_custom_dialog_basic
        end
        
        # Додаємо пункт меню "Скидання позиції"
        menu.add_item("Скидання позиції") do
          if valid_preview_state?
            reset_offset
          else
            UI.messagebox("Немає активного прев'ю. Наведіть курсор на грань деталі.")
          end
        end
        
        menu.add_separator
        menu.add_item("Перемкнути режим #{@ctrl_pressed ? 'кількості панелей' : 'зміщення панелей'}") do
          @ctrl_pressed = !@ctrl_pressed
          if @ctrl_pressed
            Sketchup.status_text = "Режим зміщення панелей увімкнено"
            Sketchup.vcb_label = "Зсув панелей (мм)"
            
            # Відразу встановлюємо зміщення на 0 і оновлюємо превью
            @offset = 0.mm
            save_offset_setting(Sketchup.active_model, "offset", "0")
            
            UI.start_timer(0) { Sketchup.vcb_value = @offset.to_mm.to_s }
          else
            Sketchup.status_text = "Режим вибору кількості панелей увімкнено"
            Sketchup.vcb_label = "Кількість панелей"
            UI.start_timer(0) { Sketchup.vcb_value = @num_panels.to_s }
          end
          @view.invalidate if @view
        end
      end

# Оновлений метод скидання зсуву для всіх напрямків
def reset_offset
  model = Sketchup.active_model
  
  # Скидаємо всі зсуви
  save_offset_setting(model, "offset", "0")
  save_settings(model, nil, nil, nil, nil, {
    left: "0",
    right: "0",
    top: "0",
    bottom: "0"
  })
  
  # Оновлюємо змінні офсету
  @offset = 0.mm
  @offset_left = 0.mm
  @offset_right = 0.mm
  @offset_top = 0.mm
  @offset_bottom = 0.mm
  
  # Оновлюємо кеш налаштувань
  @saved_settings = load_saved_settings(model)
  
  # Оновлюємо VCB і вид
  UI.start_timer(0) { Sketchup.vcb_value = @offset.to_mm.to_s }
  @view.invalidate if @view
end

def onLButtonDown(flags, x, y, view)
  @view = view
  
  if !@current_group && !@current_face
    return UI.messagebox("Немає активного прев'ю. Наведіть курсор на грань деталі.")
  elsif !@current_group 
    return UI.messagebox("Наведіть курсор на групу або компонент.")
  elsif !@current_face
    return UI.messagebox("Наведіть курсор на грань деталі.")
  elsif !find_largest_faces(@current_group).include?(@current_face)
    return UI.messagebox("Виберіть основну грань деталі. Поточна грань замала.")
  elsif !valid_preview_state?
    return UI.messagebox("Немає активного прев'ю. Наведіть курсор на основну грань деталі.")
  end
  
  # остальной код метода...
  vectors = calculate_preview_vectors
        return unless vectors
        points = create_preview_rectangle(vectors)
        return unless points
        adapt_rectangle(points, @center_point, vectors[:right], vectors[:up], view)
        extrusion_length = find_safe_extrusion_length(points[0], @face_normal, view)
        return unless extrusion_length && extrusion_length > 0
        @preview_data = { points: points, extrusion_length: extrusion_length, transformation: @full_transform, normal: @face_normal }
        @original_extrusion_vector = @face_normal.clone
        create_panel_array_with_saved_settings(view)
      end

      def onMouseMove(flags, x, y, view)
        @display_preview = false
        @center_point = nil
        @current_face = nil
        @current_group = nil
        @groups_in_path = []
        @face_normal = nil
        @full_transform = nil
        @local_axes = nil
        @wwt_attributes = {}
        @selected_material = nil
        @preview_data = nil
        @group_material = nil

        input_point = view.inputpoint(x, y)
        return unless input_point
        path = input_point.instance_path
        @groups_in_path = path.to_a.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        return if @groups_in_path.empty?
        @current_group = @groups_in_path.last
        @current_face = input_point.face
        if valid_target?
          @display_preview = true
          @center_point = input_point.position
          @full_transform = calculate_path_transformation(@groups_in_path)
          @face_normal = @current_face.normal.transform(@full_transform)
          calculate_local_axes
          analyze_group_materials(@current_group)
          
          # Змінюємо підказку відповідно до режиму
          if @ctrl_pressed
            # Для режиму зміщення показуємо зсув
            UI.start_timer(0) { Sketchup.vcb_label = "Зсув панелей (мм)"; Sketchup.vcb_value = @offset.to_mm.to_s }
            Sketchup.status_text = "Введіть значення зсуву в мм і натисніть Enter, ЛКМ для створення"
          else
            # Для режиму кількості панелей
            UI.start_timer(0) { Sketchup.vcb_label = "Кількість панелей"; Sketchup.vcb_value = @num_panels.to_s }
            Sketchup.status_text = "Введіть кількість панелей і натисніть Enter, ЛКМ для створення"
          end
        end
        view.invalidate
      end
      
      def draw(view)
        return unless valid_preview_state?
        vectors = calculate_preview_vectors
        return unless vectors
        points = create_preview_rectangle(vectors)
        return unless points
        adapt_rectangle(points, @center_point, vectors[:right], vectors[:up], view)
        extrusion_length = find_safe_extrusion_length(points[0], @face_normal, view)
        return unless extrusion_length && extrusion_length > 0
        draw_panel_array_preview(view, points, extrusion_length)
      end
      
def create_panel_array_with_saved_settings(view)
  @view = view
  model = view.model
  saved_settings = load_saved_settings(model)
  
  # Визначення імені групи
  group_name = @current_group ? @current_group.name : "Панель"
  if saved_settings[:base_name]
    group_name = saved_settings[:base_name]
  end
  
  saved_default_thickness = saved_settings[:default_thickness] || "18"
  saved_default_material = saved_settings[:default_material] || "За замовчуванням"
  saved_group_panels = saved_settings[:group_panels] || false

  # Визначення кількості панелей - в режимі Ctrl (зміщення) створюємо лише 1 панель
  num_panels = @ctrl_pressed ? 1 : @num_panels

  model.start_operation('Create Panel Array', true)
  begin
    thickness_in_mm = saved_default_thickness.to_f.mm
    
    # Визначаємо матеріал, перевіряємо на прозорість
    if saved_default_material == "За замовчуванням"
      material = nil
    elsif saved_default_material == "Default"
      material = model.materials["Default"]
    elsif saved_default_material == "Transparent"
      material = model.materials["Default"]
    else
      material = model.materials[saved_default_material]
      if material && material.name == "Transparent"
        material = model.materials["Default"]
      end
    end
    
    # Оновлюємо окремі офсети з налаштувань
    @offset_left = saved_settings[:offset_left].to_f.mm if saved_settings[:offset_left]
    @offset_right = saved_settings[:offset_right].to_f.mm if saved_settings[:offset_right]
    @offset_top = saved_settings[:offset_top].to_f.mm if saved_settings[:offset_top]
    @offset_bottom = saved_settings[:offset_bottom].to_f.mm if saved_settings[:offset_bottom]
    
    # Передаємо зсув та оновлену кількість панелей
    panels = saved_group_panels ? 
      create_grouped_panels(model, group_name, num_panels, thickness_in_mm, material, false, @offset) : 
      create_panels(model, group_name, num_panels, thickness_in_mm, false, @offset)
    
    # Додатково перевіряємо матеріали панелей
    if panels && !panels.empty?
      panels.each do |panel|
        if panel.respond_to?(:material=)
          if material && material.name != "Transparent"
            panel.material = material
          else
            panel.material = model.materials["Default"]
          end
        end
      end
      
      model.commit_operation
    else
      model.abort_operation
    end
  rescue => e
    puts "Error: #{e.message}"
    model.abort_operation
  end
  reset_tool_state
  view.invalidate
end

# Діалог базових налаштувань
def show_custom_dialog_basic
  model = Sketchup.active_model
  # Спочатку пріоритет імені з-під курсору
  group_name = @current_group ? @current_group.name : "Панель"
  # Перевіряємо, чи були попередні зміни користувачем
  if @saved_settings[:base_name]
    # Якщо ім'я було змінено користувачем, використовуємо його
    group_name = @saved_settings[:base_name]
  end
  
  saved_default_thickness = @saved_settings[:default_thickness] || "18"
  saved_default_material = @saved_settings[:default_material] || "За замовчуванням"
  saved_group_panels = @saved_settings[:group_panels] || false
  
  # Завантажуємо збережені значення офсетів
  offset_left = @saved_settings[:offset_left] || "0"
  offset_right = @saved_settings[:offset_right] || "0"
  offset_top = @saved_settings[:offset_top] || "0"
  offset_bottom = @saved_settings[:offset_bottom] || "0"
  
  # Створюємо діалог налаштувань
  dialog_class = defined?(UI::HtmlDialog) ? UI::HtmlDialog : UI::WebDialog
  
  # Завантаження збережених розмірів та позиції діалогу
  width = @saved_settings[:basic_dialog_width] || 400
  height = @saved_settings[:basic_dialog_height] || 500
  left = @saved_settings[:basic_dialog_left] || 200
  top = @saved_settings[:basic_dialog_top] || 200
  
  # Створення діалогу
  basic_dialog = dialog_class.new({
    :dialog_title => "Налаштування масиву панелей",
    :scrollable => true,
    :resizable => true,
    :width => width,
    :height => height
  })
  
  # Встановлюємо позицію діалогу
  basic_dialog.set_position(left, top)
  
  # Отримуємо список матеріалів моделі
  materials_list = get_all_model_materials()
  materials_options = materials_list.map { |m| "<option value=\"#{m}\" #{saved_default_material == m ? 'selected' : ''}>#{m}</option>" }.join
  
  # HTML для діалогу з діаграмою і автозбереженням
  html = <<-HTML
  <!DOCTYPE html>
  <html>
  <head>
    <meta charset="UTF-8">
    <style>
      body { font-family: "Century Gothic", Arial, sans-serif; font-size: 12px; padding: 10px; background: #f5f5f5; }
      .form-row { margin-bottom: 15px; display: flex; align-items: center; } 
      label { display: inline-block; width: 100px; }
      input[type="text"], select { width: 80px; padding: 3px; border: 1px solid #e0e0e0; font-size: 12px; }
      .checkbox-row { display: flex; align-items: center; margin-bottom: 15px; }
      .checkbox-row input { margin-right: 10px; }
      .buttons { display: flex; justify-content: flex-end; margin-top: 20px; }
      button { padding: 4px 8px; background: #e0e0e0; border: none; border-radius: 3px; margin-left: 10px; cursor: pointer; }
      button:hover { background: #d0d0d0; }
      .help-text { font-size: 11px; color: #777; margin-top: 5px; }
      .section-title { font-weight: bold; margin-top: 15px; margin-bottom: 10px; }
      .success-message { background: #e7f7e7; color: #287a28; padding: 5px; border-radius: 3px; margin-top: 5px; display: none; }
      .diagram { text-align: center; margin: 15px 0; padding: 10px; background: #fff; border-radius: 3px; border: 1px solid #e0e0e0; }
      .diagram-title { font-weight: bold; margin-bottom: 8px; font-size: 11px; color: #555; }
    </style>
  </head>
  <body>
    <form id="settingsForm">
      <div class="form-row">
        <label for="base_name">Базова назва:</label>
        <input type="text" id="base_name" value="#{group_name}" oninput="autoSaveSettings()">
      </div>
      
      <div class="form-row">
        <label for="thickness">Товщина (мм):</label>
        <input type="text" id="thickness" value="#{saved_default_thickness}" oninput="autoSaveSettings()">
      </div>
      
      <div class="form-row">
        <label for="material">Матеріал:</label>
        <select id="material" onchange="autoSaveSettings()">
          #{materials_options}
        </select>
      </div>
      
      <div class="checkbox-row">
        <input type="checkbox" id="group_panels" #{saved_group_panels ? 'checked' : ''} onchange="autoSaveSettings()">
        <label for="group_panels">Згрупувати панелі</label>
      </div>
      
      <div class="section-title">Зсуви панелей по периметру (мм):</div>
      
      <div class="form-row">
        <label for="offset_left">Лівий зсув:</label>
        <input type="text" id="offset_left" value="#{offset_left}" oninput="autoSaveSettings()">
      </div>
      
      <div class="form-row">
        <label for="offset_right">Правий зсув:</label>
        <input type="text" id="offset_right" value="#{offset_right}" oninput="autoSaveSettings()">
      </div>
      
      <div class="form-row">
        <label for="offset_bottom">Нижній зсув:</label>
        <input type="text" id="offset_bottom" value="#{offset_bottom}" oninput="autoSaveSettings()">
      </div>
      
      <div class="form-row">
        <label for="offset_top">Верхній зсув:</label>
        <input type="text" id="offset_top" value="#{offset_top}" oninput="autoSaveSettings()">
      </div>
      
      <div class="help-text">
        Додатні значення збільшують розмір панелей, від'ємні - зменшують.<br>
        Зсуви застосовуються до всіх панелей, незалежно від режиму зсуву.
      </div>
      
      <div id="saveMessage" class="success-message">Налаштування збережено</div>
      
      <div class="buttons">
        <button type="button" id="cancel">Скасувати</button>
        <button type="button" id="apply">Застосувати</button>
      </div>
    </form>
    
    <script>
      // Debounce function to prevent too many calls
      function debounce(func, wait) {
        let timeout;
        return function() {
          const context = this;
          const args = arguments;
          clearTimeout(timeout);
          timeout = setTimeout(() => {
            func.apply(context, args);
          }, wait);
        };
      }
      
      // Auto-save function
      const autoSaveSettings = debounce(function() {
        var settings = {
          base_name: document.getElementById('base_name').value,
          thickness: document.getElementById('thickness').value,
          material: document.getElementById('material').value,
          group_panels: document.getElementById('group_panels').checked,
          offset_left: document.getElementById('offset_left').value,
          offset_right: document.getElementById('offset_right').value,
          offset_top: document.getElementById('offset_top').value,
          offset_bottom: document.getElementById('offset_bottom').value
        };
        
        // Call Ruby method to save settings
        window.location.href = 'skp:auto_save_settings@' + JSON.stringify(settings);
        
        // Show saved message
        var saveMessage = document.getElementById('saveMessage');
        saveMessage.style.display = 'block';
        setTimeout(function() {
          saveMessage.style.display = 'none';
        }, 1500);
      }, 300);
      
      // Apply button - doesn't close dialog
      document.getElementById('apply').addEventListener('click', function(e) {
        e.preventDefault();
        var settings = {
          base_name: document.getElementById('base_name').value,
          thickness: document.getElementById('thickness').value,
          material: document.getElementById('material').value,
          group_panels: document.getElementById('group_panels').checked,
          offset_left: document.getElementById('offset_left').value,
          offset_right: document.getElementById('offset_right').value,
          offset_top: document.getElementById('offset_top').value,
          offset_bottom: document.getElementById('offset_bottom').value
        };
        window.location.href = 'skp:apply_settings@' + JSON.stringify(settings);
      });
      
      // Cancel button - close dialog
      document.getElementById('cancel').addEventListener('click', function(e) {
        e.preventDefault();
        window.location.href = 'skp:cancel_dialog@';
      });
      
      // Submit form with Enter key
      document.getElementById('settingsForm').addEventListener('submit', function(e) {
        e.preventDefault();
        document.getElementById('apply').click();
      });
    </script>
  </body>
  </html>
  HTML
  
  basic_dialog.set_html(html)
  
  # Додаємо обробник зміни розміру діалогу
  if basic_dialog.respond_to?(:set_on_resize)
    basic_dialog.set_on_resize do |d, w, h|
      WWT_CreatePanelsTools::WWT_CreatePanelArray.save_dialog_size(Sketchup.active_model, "basic", w, h)
    end
  end
  
  # Додаємо обробник переміщення діалогу
  if basic_dialog.respond_to?(:set_on_move)
    basic_dialog.set_on_move do |d, left, top|
      WWT_CreatePanelsTools::WWT_CreatePanelArray.save_dialog_position(Sketchup.active_model, "basic", left, top)
    end
  end
  
  # Обробник автозбереження налаштувань
  basic_dialog.add_action_callback("auto_save_settings") do |_, data|
    begin
      settings = JSON.parse(data)
      model = Sketchup.active_model
      
      # Зберігаємо налаштування
      save_settings(model, 
        settings["thickness"], 
        settings["material"], 
        settings["group_panels"], 
        settings["base_name"]
      )
      
      # Зберігаємо офсети
      save_settings(model, nil, nil, nil, nil, {
        left: settings["offset_left"],
        right: settings["offset_right"],
        top: settings["offset_top"],
        bottom: settings["offset_bottom"]
      })
      
      # Оновлюємо змінні офсетів в інструменті
      @offset_left = settings["offset_left"].to_f.mm
      @offset_right = settings["offset_right"].to_f.mm
      @offset_top = settings["offset_top"].to_f.mm
      @offset_bottom = settings["offset_bottom"].to_f.mm
      
      # Розраховуємо сумарний офсет для сумісності
      total_offset = settings["offset_left"].to_f.abs + 
                     settings["offset_right"].to_f.abs + 
                     settings["offset_top"].to_f.abs + 
                     settings["offset_bottom"].to_f.abs
      
      # Зберігаємо сумарний офсет окремо, але НЕ змінюємо @offset в режимі зсуву
      save_offset_setting(model, "offset", total_offset.to_s)
      
      # Змінюємо @offset тільки якщо НЕ в режимі зсуву
      if !@ctrl_pressed
        @offset = total_offset.to_f.mm
      end
      
      # Оновлюємо змінну базової назви
      @base_name = settings["base_name"]
      
      # Оновлюємо кеш налаштувань
      refresh_saved_settings
      
      # Оновлюємо вид
      @view.invalidate if @view
    rescue => e
      puts "Auto-save error: #{e.message}"
    end
  end
  
  # Обробник застосування налаштувань
  basic_dialog.add_action_callback("apply_settings") do |_, data|
    begin
      settings = JSON.parse(data)
      model = Sketchup.active_model
      
      # Зберігаємо налаштування
      save_settings(model, 
        settings["thickness"], 
        settings["material"], 
        settings["group_panels"], 
        settings["base_name"]
      )
      
      # Зберігаємо офсети
      save_settings(model, nil, nil, nil, nil, {
        left: settings["offset_left"],
        right: settings["offset_right"],
        top: settings["offset_top"],
        bottom: settings["offset_bottom"]
      })
      
      # Оновлюємо змінні офсетів в інструменті
      @offset_left = settings["offset_left"].to_f.mm
      @offset_right = settings["offset_right"].to_f.mm
      @offset_top = settings["offset_top"].to_f.mm
      @offset_bottom = settings["offset_bottom"].to_f.mm
      
      # Розраховуємо сумарний офсет для сумісності
      total_offset = settings["offset_left"].to_f.abs + 
                     settings["offset_right"].to_f.abs + 
                     settings["offset_top"].to_f.abs + 
                     settings["offset_bottom"].to_f.abs
      
      # Зберігаємо сумарний офсет окремо, але НЕ змінюємо @offset в режимі зсуву
      save_offset_setting(model, "offset", total_offset.to_s)
      
      # Змінюємо @offset тільки якщо НЕ в режимі зсуву
      if !@ctrl_pressed
        @offset = total_offset.to_f.mm
      end
      
      # Оновлюємо змінну базової назви
      @base_name = settings["base_name"]
      
      # Зберігаємо поточну позицію та розміри діалогу
      if basic_dialog.respond_to?(:get_position)
        left, top = basic_dialog.get_position
        WWT_CreatePanelsTools::WWT_CreatePanelArray.save_dialog_position(model, "basic", left, top)
      end
      
      if basic_dialog.respond_to?(:get_size)
        width, height = basic_dialog.get_size
        WWT_CreatePanelsTools::WWT_CreatePanelArray.save_dialog_size(model, "basic", width, height)
      end
      
      # Оновлюємо збережені налаштування
      refresh_saved_settings
      
      # Оновлюємо вид (НЕ закриваємо діалог)
      @view.invalidate if @view
    rescue => e
      UI.messagebox("Помилка застосування налаштувань: #{e.message}")
    end
  end
  
  # Обробник скасування
  basic_dialog.add_action_callback("cancel_dialog") do |_|
    model = Sketchup.active_model
    
    # Зберігаємо поточну позицію та розміри діалогу перед закриттям
    if basic_dialog.respond_to?(:get_position)
      left, top = basic_dialog.get_position
      WWT_CreatePanelsTools::WWT_CreatePanelArray.save_dialog_position(model, "basic", left, top)
    end
    
    if basic_dialog.respond_to?(:get_size)
      width, height = basic_dialog.get_size
      WWT_CreatePanelsTools::WWT_CreatePanelArray.save_dialog_size(model, "basic", width, height)
    end
    
    # Оновлюємо збережені налаштування
    refresh_saved_settings
    
    # Закриваємо діалог
    basic_dialog.close
  end
  
  # Зберігаємо посилання на діалог для закриття при деактивації
  @basic_dialog = basic_dialog
  
  # Показуємо діалог
  basic_dialog.show
end

# Метод для збереження налаштування зсуву
def save_offset_setting(model, offset_type, offset_value)
  dict = model.attribute_dictionary("WWT_CreatePanelArray_Settings", true)
  dict[offset_type] = offset_value
  # Оновлюємо кеш налаштувань
  @saved_settings = load_saved_settings(model)
end

# Оновлений метод створення панелей з урахуванням зсуву
def create_panels(model, base_name, num_panels, thickness, no_gaps = false, custom_offset = nil)
  dimensions = calculate_min_dimension(@current_group)
  direction = determine_direction(@face_normal)
  array_params = calculate_array_parameters(dimensions, num_panels, thickness, no_gaps)
  
  # Застосування зсуву
  offset = custom_offset || @offset
  array_params[:offset] = offset
  
  panels = []
  num_panels.times do |i|
    panel = create_single_panel(model, base_name, i + 1, thickness, array_params, direction, no_gaps)
    apply_materials_and_attributes(panel) if panel
    panels << panel if panel
  end
  panels
end

# Оновлений метод для створення згрупованих панелей з урахуванням зсуву
def create_grouped_panels(model, base_name, num_panels, thickness, material = nil, no_gaps = false, custom_offset = nil)
  parent_group = @groups_in_path[-2] if @groups_in_path.size > 1
  dimensions = calculate_min_dimension(@current_group)
  direction = determine_direction(@face_normal)
  array_params = calculate_array_parameters(dimensions, num_panels, thickness, no_gaps)
  
  # Застосування зсуву
  offset = custom_offset || @offset
  array_params[:offset] = offset
  
  main_group = parent_group ? parent_group.entities.add_group : model.active_entities.add_group
  main_group.name = base_name
  main_group.material = material if material
  
  panels = []
  num_panels.times do |i|
    panel = create_single_panel_inside_group(model, main_group, base_name, i + 1, thickness, array_params, direction, no_gaps, material)
    apply_materials_and_attributes(panel, material) if panel
    panels << panel if panel
  end
  main_group = move_to_parent_group(main_group, parent_group) if parent_group
  [main_group]
end

# Модифікований метод create_single_panel для врахування розмірних зсувів
def create_single_panel(model, base_name, index, thickness, params, direction, no_gaps = false)
  parent_group = @groups_in_path[-2] if @groups_in_path.size > 1
  # Визначаємо entities для parent_group
  parent_entities = if parent_group
    parent_group.is_a?(Sketchup::ComponentInstance) ? parent_group.definition.entities : parent_group.entities
  else
    model.active_entities
  end
  
  panel_group = parent_entities.add_group
  panel_group.name = "#{base_name}_#{index}"
  base_points = params[:base_points].map(&:clone)
  original_vector = params[:extrusion_vector].clone
  
  # Налаштування вектора екструзії
  @positive_extrusion_vector ||= original_vector.clone.tap { |v| v.x = v.x.abs; v.y = v.y.abs; v.z = v.z.abs; v.normalize!.length = 1.0 }
  x_dir = @x_direction || (original_vector.x <=> 0)
  y_dir = @y_direction || (original_vector.y <=> 0)
  z_dir = @z_direction || (original_vector.z <=> 0)
  @x_direction, @y_direction, @z_direction = x_dir, y_dir, z_dir
  
  # Функція для створення вектора екструзії
  create_vector = lambda do |length|
    vector = @positive_extrusion_vector.clone
    vector.length = length
    vector.x *= x_dir if vector.x != 0 && x_dir != 0
    vector.y *= y_dir if vector.y != 0 && y_dir != 0
    vector.z *= z_dir if vector.z != 0 && z_dir != 0
    vector
  end
  
  # Застосування зсуву і режиму для базової відстані
  offset_value = params[:offset] || 0.mm
  
  if @ctrl_pressed
    # У режимі зміщення, починаємо від 0 + зсув
    position = offset_value + (no_gaps ? (thickness * (index - 1)) : (params[:spacing] * (index - 1) + thickness * (index - 1)))
  else
    # У звичайному режимі, розподіляємо зі зсувом
    position = no_gaps ? (thickness * (index - 1)) : (params[:spacing] * index + thickness * (index - 1))
    position += offset_value  # Додаємо зсув до позиції
  end
  
  # Розташування панелі
  global_points = base_points.map { |p| p.offset(create_vector.call(position)) }
  
  # Визначаємо напрямки панелі
  directions = determine_panel_directions(global_points, original_vector)
  
  # Застосовуємо зсуви для кожної сторони
  if @offset_left != 0.mm || @offset_right != 0.mm || @offset_top != 0.mm || @offset_bottom != 0.mm
    global_points = apply_offset_to_points(
      global_points, 
      directions, 
      @offset_left, 
      @offset_right, 
      @offset_top, 
      @offset_bottom
    )
  end
  
  # Перевіряємо, чи маємо достатньо унікальних точок для створення грані
  return nil if global_points.uniq.length < 3
  
  # Створюємо трансформацію і додаємо грань
  tr = Geom::Transformation.axes(global_points[0], @local_axes[:x], @local_axes[:y], @local_axes[:z])
  panel_group.transformation = tr
  points = global_points.map { |p| p.transform(tr.inverse) }
  face = panel_group.entities.add_face(points)
  return nil unless face&.valid?
  
  # Забезпечуємо правильну орієнтацію грані і витягуємо її на товщину
  face.reverse! if face.normal.dot(original_vector) < 0
  face.pushpull(thickness)
  
  # Обробляємо parent_group і копіюємо текстури
  panel_group = move_to_parent_group(panel_group, parent_group) if parent_group
  panel_entities = panel_group.is_a?(Sketchup::ComponentInstance) ? panel_group.definition.entities : panel_group.entities
  target_face = panel_entities.grep(Sketchup::Face).find { |f| f.normal.samedirection?(original_vector) }
  
  copy_texture_mapping(@current_face, target_face) if @current_face && target_face && @view
  panel_group
end

# Метод для створення панелі всередині групи з урахуванням зсуву
def create_single_panel_inside_group(model, main_group, base_name, index, thickness, params, direction, no_gaps, material)
  # Визначаємо entities для main_group
  main_entities = main_group.is_a?(Sketchup::ComponentInstance) ? main_group.definition.entities : main_group.entities
  
  panel_group = main_entities.add_group
  panel_group.name = "#{base_name}_#{index}"
  panel_group.material = material if material
  base_points = params[:base_points].map(&:clone)
  original_vector = params[:extrusion_vector].clone
  
  # Застосовуємо зсув і режим
  offset_value = params[:offset] || 0.mm
  
  if @ctrl_pressed
    # У режимі зміщення, починаємо від 0 + зсув
    position = offset_value + (no_gaps ? (thickness * (index - 1)) : (params[:spacing] * (index - 1) + thickness * (index - 1)))
  else
    # У звичайному режимі, розподіляємо зі зсувом
    position = no_gaps ? (thickness * (index - 1)) : (params[:spacing] * index + thickness * (index - 1))
    position += offset_value  # Додаємо зсув до позиції
  end
  
  # Створюємо вектор позиції панелі
  panel_vector = original_vector.clone.tap { |v| v.length = position }
  
  # Розташування панелі
  global_points = base_points.map { |p| p.offset(panel_vector) }
  
  # Визначаємо напрямки панелі відносно її орієнтації
  directions = determine_panel_directions(global_points, original_vector)
  
  # Застосовуємо зсуви для кожної сторони
  if @offset_left != 0.mm || @offset_right != 0.mm || @offset_top != 0.mm || @offset_bottom != 0.mm
    global_points = apply_offset_to_points(
      global_points, 
      directions, 
      @offset_left, 
      @offset_right, 
      @offset_top, 
      @offset_bottom
    )
  end
  
  # Трансформуємо глобальні точки в локальні координати групи
  local_points = global_points.map { |p| p.transform(main_group.transformation.inverse) }
  
  # Створюємо грань та екструдуємо її
  face = panel_group.entities.add_face(local_points)
  return nil unless face&.valid?
  face.reverse! if face.normal.dot(original_vector.transform(main_group.transformation.inverse)) < 0
  face.pushpull(thickness)
  
  # Отримуємо entities для panel_group
  panel_entities = panel_group.is_a?(Sketchup::ComponentInstance) ? panel_group.definition.entities : panel_group.entities
  target_face = panel_entities.grep(Sketchup::Face).find { |f| f.normal.samedirection?(original_vector.transform(main_group.transformation.inverse)) }
  
  copy_texture_mapping(@current_face, target_face) if @current_face && target_face
  panel_group
end
      
# Завершення методу draw_panel_array_preview
# Завершення методу draw_panel_array_preview
def draw_panel_array_preview(view, base_points, total_depth)
  model = view.model
  saved_settings = load_saved_settings(model)
  default_thickness = (saved_settings[:default_thickness] || "18").to_f.mm
  
  # Отримуємо зсув
  offset_value = @offset
  
  # Кількість панелей залежить від режиму
  # У режимі Ctrl (зміщення) завжди відображаємо лише 1 панель
  num_panels = @ctrl_pressed ? 1 : @num_panels
  
  # Налаштування векторів екструзії
  @original_extrusion_vector = @face_normal.clone
  @positive_extrusion_vector = @face_normal.clone
  @positive_extrusion_vector.x = @positive_extrusion_vector.x.abs
  @positive_extrusion_vector.y = @positive_extrusion_vector.y.abs
  @positive_extrusion_vector.z = @positive_extrusion_vector.z.abs
  @positive_extrusion_vector.normalize!.length = 1.0
  @x_direction = @original_extrusion_vector.x <=> 0
  @y_direction = @original_extrusion_vector.y <=> 0
  @z_direction = @original_extrusion_vector.z <=> 0
  
  # Налаштування кольорів та стилів
  if @ctrl_pressed
    # Рожевий колір для режиму зміщення (Ctrl натиснуто)
    outline_color = [255, 105, 180, 255]  # Рожевий контур
    fill_color = [255, 105, 180, 85]      # Рожевий з такою ж прозорістю як і помаранчевий
  else
    # Залишаємо помаранчевий для звичайного режиму
    outline_color = [255, 120, 0, 255]    # Помаранчевий контур
    fill_color = [255, 120, 0, 85]        # Помаранчевий напівпрозорий
  end

  view.line_width = 2
  @preview_panel_positions = []
  @preview_panel_thicknesses = []
  
  # Функція для створення векторів з урахуванням напрямку
  create_vector = lambda do |length|
    vector = @positive_extrusion_vector.clone
    vector.length = length
    vector.x *= @x_direction if vector.x != 0 && @x_direction != 0
    vector.y *= @y_direction if vector.y != 0 && @y_direction != 0
    vector.z *= @z_direction if vector.z != 0 && @z_direction != 0
    vector
  end
  
  # Малюємо панелі з проміжками
  panel_thickness = default_thickness
  @preview_panel_thicknesses = Array.new(num_panels, panel_thickness)
  total_panels_thickness = num_panels * panel_thickness
  
  # Різні алгоритми розміщення залежно від режиму
  if @ctrl_pressed
    # У режимі зміщення, розміщуємо ОДНУ панель на позиції offset_value
    position = offset_value
    @preview_panel_positions << position
    
    # Створюємо вектор позиції та розміщуємо панель
    panel_vector = create_vector.call(position)
    panel_base_points = base_points.map { |p| p.offset(panel_vector) }
    
    # Визначаємо напрямки панелі
    directions = determine_panel_directions(panel_base_points, @original_extrusion_vector)
    
    # Застосовуємо офсети, якщо вони задані
    if @offset_left != 0.mm || @offset_right != 0.mm || @offset_top != 0.mm || @offset_bottom != 0.mm
      panel_base_points = apply_offset_to_points(
        panel_base_points, 
        directions, 
        @offset_left, 
        @offset_right, 
        @offset_top, 
        @offset_bottom
      )
    end
    
    # Створюємо верхню грань панелі
    panel_top_points = panel_base_points.map { |p| p.offset(create_vector.call(panel_thickness)) }
    
    # Малюємо панель
    view.drawing_color = fill_color
    view.draw(GL_QUADS, panel_base_points)
    view.draw(GL_QUADS, panel_top_points)
    4.times do |j|
      view.draw(GL_QUADS, [
        panel_base_points[j], 
        panel_base_points[(j + 1) % 4], 
        panel_top_points[(j + 1) % 4], 
        panel_top_points[j]
      ])
    end
    
    # Малюємо контур панелі
    view.drawing_color = outline_color
    4.times do |j|
      view.draw_line(panel_base_points[j], panel_base_points[(j + 1) % 4])
      view.draw_line(panel_top_points[j], panel_top_points[(j + 1) % 4])
      view.draw_line(panel_base_points[j], panel_top_points[j])
    end
  else
    # У звичайному режимі, розміщуємо панелі рівномірно з проміжками
    gap = (total_depth - total_panels_thickness) / (num_panels + 1)
    
    num_panels.times do |i|
      position = gap * (i + 1) + panel_thickness * i
      position += offset_value  # Додаємо зсув до позиції
      @preview_panel_positions << position
      
      # Створюємо вектор позиції та розміщуємо панель
      panel_vector = create_vector.call(position)
      panel_base_points = base_points.map { |p| p.offset(panel_vector) }
      
      # Визначаємо напрямки панелі
      directions = determine_panel_directions(panel_base_points, @original_extrusion_vector)
      
      # Застосовуємо офсети, якщо вони задані
      if @offset_left != 0.mm || @offset_right != 0.mm || @offset_top != 0.mm || @offset_bottom != 0.mm
        panel_base_points = apply_offset_to_points(
          panel_base_points, 
          directions, 
          @offset_left, 
          @offset_right, 
          @offset_top, 
          @offset_bottom
        )
      end
      
      # Створюємо верхню грань панелі
      panel_top_points = panel_base_points.map { |p| p.offset(create_vector.call(panel_thickness)) }
      
      # Малюємо панель
      view.drawing_color = fill_color
      view.draw(GL_QUADS, panel_base_points)
      view.draw(GL_QUADS, panel_top_points)
      4.times do |j|
        view.draw(GL_QUADS, [
          panel_base_points[j], 
          panel_base_points[(j + 1) % 4], 
          panel_top_points[(j + 1) % 4], 
          panel_top_points[j]
        ])
      end
      
      # Малюємо контур панелі
      view.drawing_color = outline_color
      4.times do |j|
        view.draw_line(panel_base_points[j], panel_base_points[(j + 1) % 4])
        view.draw_line(panel_top_points[j], panel_top_points[(j + 1) % 4])
        view.draw_line(panel_base_points[j], panel_top_points[j])
      end
    end
  end
end

# Метод для знаходження центру панелі
def calculate_center(points)
  center = Geom::Point3d.new(0, 0, 0)
  points.each do |p|
    center.x += p.x
    center.y += p.y
    center.z += p.z
  end
  center.x /= points.length
  center.y /= points.length
  center.z /= points.length
  center
end

# Метод для знаходження сторін панелі
def find_panel_edges(points)
  edges = []
  lengths = []
  vectors = []
  for i in 0...points.length
    j = (i + 1) % points.length
    edge = [points[i], points[j]]
    vector = points[i].vector_to(points[j])
    length = vector.length
    edges << edge
    lengths << length
    vectors << vector
  end
  return edges, lengths, vectors
end

# Метод для визначення, чи є один вектор перпендикулярним до іншого
def is_perpendicular?(vector1, vector2, tolerance = 0.1)
  vector1.normalize!
  vector2.normalize!
  (vector1.dot(vector2)).abs < tolerance
end

# Метод для створення перпендикулярного вектора
def create_perpendicular_vector(vector, normal)
  # Використовуємо векторний добуток для створення перпендикулярного вектора
  perpendicular = vector.cross(normal)
  perpendicular.normalize!
  perpendicular
end

# Додаємо метод для оновлення збережених налаштувань
def refresh_saved_settings
  @saved_settings = load_saved_settings(Sketchup.active_model)
end

def reset_tool_state
  @display_preview = false
  @center_point = nil
  @current_face = nil
  @current_group = nil
  @groups_in_path = []
  @face_normal = nil
  @full_transform = nil
  @local_axes = nil
  @wwt_attributes = {}
  @selected_material = nil
  @preview_data = nil
  @group_material = nil
  # Не скидаємо @ctrl_pressed, @num_panels і офсети
  # Завантажуємо збережені налаштування
  @saved_settings = load_saved_settings(Sketchup.active_model) if @saved_settings.nil?
  
  # Завантажуємо значення офсетів з налаштувань
  if @saved_settings
    @offset_left = @saved_settings[:offset_left].to_f.mm if @saved_settings[:offset_left]
    @offset_right = @saved_settings[:offset_right].to_f.mm if @saved_settings[:offset_right]
    @offset_top = @saved_settings[:offset_top].to_f.mm if @saved_settings[:offset_top]
    @offset_bottom = @saved_settings[:offset_bottom].to_f.mm if @saved_settings[:offset_bottom]
  end
end

def hide_abf_groups
  model = Sketchup.active_model
  @hidden_abf_groups = []
  process_entities = lambda do |entities|
    entities.each do |entity|
      if (entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)) && entity.name&.include?("_ABF")
        @hidden_abf_groups << entity
        entity.visible = false
      end
      if entity.is_a?(Sketchup::Group)
        process_entities.call(entity.entities)
      elsif entity.is_a?(Sketchup::ComponentInstance)
        process_entities.call(entity.definition.entities)
      end
    end
  end
  process_entities.call(model.active_entities)
end

def show_abf_groups
  @hidden_abf_groups.each { |entity| entity.visible = true if entity.valid? }
  @hidden_abf_groups.clear
end

def valid_target?
  @current_group && @current_face && find_largest_faces(@current_group).include?(@current_face) && !@current_face.edges.empty?
end

def valid_preview_state?
  @display_preview && @center_point && @face_normal && @local_axes
end

def calculate_path_transformation(path)
  path.inject(Geom::Transformation.new) { |total_transform, entity| entity.respond_to?(:transformation) ? total_transform * entity.transformation : total_transform }
end

def calculate_local_axes
  @local_axes = { x: @full_transform.xaxis, y: @full_transform.yaxis, z: @full_transform.zaxis }
  @display_preview = false unless @local_axes.values.all? { |v| v&.valid? && v.length > 0.000001 }
end

def calculate_preview_vectors
  dot_products = @local_axes.map { |axis, vector| [axis, vector.dot(@face_normal).abs] }.to_h
  main_axis = dot_products.max_by { |_, dot| dot }[0]
  available_axes = @local_axes.reject { |axis, _| axis == main_axis }.values
  return nil if available_axes.size < 2
  right_vector = safe_normalize(available_axes[0].clone, 2.mm)
  up_vector = safe_normalize(available_axes[1].clone, 1.mm)
  { right: right_vector, up: up_vector } if right_vector && up_vector
end

def create_preview_rectangle(vectors)
  return nil unless vectors[:right] && vectors[:up]
  [@center_point - vectors[:right] - vectors[:up], @center_point + vectors[:right] - vectors[:up], @center_point + vectors[:right] + vectors[:up], @center_point - vectors[:right] + vectors[:up]]
end

def find_safe_extrusion_length(start_point, direction, view)
  distances = find_ray_distance(start_point, direction, view)
  distances.empty? ? nil : distances.min
end

def safe_normalize(vector, length)
  return nil unless vector&.valid? && vector.length > 0.000001
  vector.normalize!.length = length
  vector
rescue
  nil
end

def find_largest_faces(group)
  return [] unless group.is_a?(Sketchup::Group) || group.is_a?(Sketchup::ComponentInstance)
  entities = group.is_a?(Sketchup::ComponentInstance) ? group.definition.entities : group.entities
  
  # Увеличиваем до 5 или более граней вместо двух
  all_faces = entities.grep(Sketchup::Face)
  largest_area = all_faces.map(&:area).max || 0
  
  # Принимаем грани, площадь которых не менее 20% от самой большой
  all_faces.select { |face| face.area >= largest_area * 0.2 }
end
      
def adapt_rectangle(points, center, right_vector, up_vector, view)
  distances = {
    right: find_ray_distance(center, right_vector, view),
    left: find_ray_distance(center, right_vector.reverse, view),
    up: find_ray_distance(center, up_vector, view),
    down: find_ray_distance(center, up_vector.reverse, view)
  }
  points[0] = points[3] = center.offset(right_vector.reverse, distances[:left].min) if distances[:left].min > 0
  points[1] = points[2] = center.offset(right_vector, distances[:right].min) if distances[:right].min > 0
  points[0] = points[0].offset(up_vector.reverse, distances[:down].min) if distances[:down].min > 0
  points[1] = points[1].offset(up_vector.reverse, distances[:down].min) if distances[:down].min > 0
  points[2] = points[2].offset(up_vector, distances[:up].min) if distances[:up].min > 0
  points[3] = points[3].offset(up_vector, distances[:up].min) if distances[:up].min > 0
end

def find_ray_distance(point, direction, view)
  distances = []
  max_attempts = 10
  step_size = 10.mm
  current_point = point.clone
  max_attempts.times do
    hit = view.model.raytest([current_point, direction], true)
    distances << current_point.distance(hit[0]) if hit
    break if hit
    current_point = current_point.offset(direction, step_size)
  end
  distances.empty? ? [0.mm] : distances
end

def calculate_array_parameters(dimensions, num_panels, thickness, no_gaps)
  total_depth = @preview_data[:extrusion_length]
  gap = no_gaps ? 0.mm : (total_depth - num_panels * thickness) / (num_panels + 1)
  { 
    total_size: total_depth, 
    panel_size: thickness, 
    spacing: gap, 
    extrusion_vector: @preview_data[:normal].clone, 
    base_points: @preview_data[:points], 
    extrusion_length: @preview_data[:extrusion_length], 
    no_gaps: no_gaps, 
    offset: 0.mm  # Початковий зсув
  }
end

def determine_direction(normal)
  extrusion_vector = @preview_data[:normal].clone
  @original_extrusion_vector = extrusion_vector.clone
  dot_products = { 'X' => extrusion_vector.dot(Geom::Vector3d.new(1, 0, 0)), 'Y' => extrusion_vector.dot(Geom::Vector3d.new(0, 1, 0)), 'Z' => extrusion_vector.dot(Geom::Vector3d.new(0, 0, 1)) }
  main_dir, value = dot_products.max_by { |_, v| v.abs }
  @extrusion_direction = value >= 0 ? main_dir : "-#{main_dir}"
end

def move_to_parent_group(group, parent_group)
  return group unless group && parent_group
  # Правильно створюємо новий екземпляр залежно від типу об'єкта
  if parent_group.is_a?(Sketchup::ComponentInstance)
    new_group = parent_group.definition.entities.add_instance(group.definition, parent_group.transformation.inverse * group.transformation)
  else
    new_group = parent_group.entities.add_instance(group.definition, parent_group.transformation.inverse * group.transformation)
  end
  new_group.name = group.name
  new_group.material = group.material if group.material
  group.erase!
  new_group
rescue
  group
end

def determine_panel_directions(points, face_normal)
  # Знаходимо центр панелі
  center = calculate_center(points)
  
  # Визначаємо вектори сторін панелі
  edges, lengths, vectors = find_panel_edges(points)
  
  # Знаходимо напрямки координатних осей панелі
  # Сортуємо сторони за довжиною (найдовша перша)
  sorted_by_length = lengths.each_with_index.sort.reverse.map { |_, idx| idx }
  
  # Індекси сторін, що відповідають за довжину/ширину
  width_edge_idx = sorted_by_length[0]  # Ширина (горизонталь) - найдовша сторона
  height_edge_idx = sorted_by_length[1] # Висота (вертикаль) - друга за довжиною
  
  # Вектори сторін панелі
  width_vector = vectors[width_edge_idx].normalize
  height_vector = vectors[height_edge_idx].normalize
  
  # Перевіряємо, чи вектори перпендикулярні
  if width_vector.dot(height_vector).abs > 0.1
    # Якщо ні, створюємо правильний перпендикулярний вектор
    # Використовуємо нормаль як опорний вектор
    height_vector = width_vector.cross(face_normal).normalize
  end
  
  # Структура з визначеними напрямками та групами точок
  directions = {
    width_vector: width_vector,
    height_vector: height_vector,
    center: center,
    left_points: [],
    right_points: [],
    top_points: [],
    bottom_points: []
  }
  
  # Класифікуємо кожну точку відносно центру
  points.each_with_index do |point, idx|
    vector_to_center = point.vector_to(center)
    
    # Горизонтальний напрямок (ширина)
    horz_proj = width_vector.dot(vector_to_center)
    if (horz_proj < 0)
      directions[:left_points] << idx
    else
      directions[:right_points] << idx
    end
    
    # Вертикальний напрямок (висота)
    vert_proj = height_vector.dot(vector_to_center)
    if (vert_proj < 0)
      directions[:bottom_points] << idx
    else
      directions[:top_points] << idx
    end
  end
  
  directions
end

# Оновлений метод для застосування офсетів до точок панелі з виправленою орієнтацією
def apply_offset_to_points(points, directions, offset_left, offset_right, offset_top, offset_bottom)
  # Створюємо копію точок для модифікації
  modified_points = points.map(&:clone)
  
  # Отримуємо опорні вектори
  width_vector = directions[:width_vector]
  height_vector = directions[:height_vector]
  
  # Визначаємо орієнтацію панелі
  orientation = determine_panel_orientation
  is_horizontal = orientation[:is_horizontal]
  
  # Визначаємо, які зсуви застосовувати в яких напрямках
  if is_horizontal
    # Для горизонтальних панелей використовуємо стандартні зсуви
    left_offset = offset_left
    right_offset = offset_right
    top_offset = offset_top
    bottom_offset = offset_bottom
  else
    # Для вертикальних панелей міняємо зсуви відповідно до орієнтації
    # FIXED: Corrected top/bottom mappings for vertical panels
    left_offset = offset_bottom  # Лівий = Нижній
    right_offset = offset_top    # Правий = Верхній
    top_offset = offset_left     # Верхній = Лівий
    bottom_offset = offset_right # Нижній = Правий
  end
  
  # Лівий зсув
  if (left_offset != 0.mm)
    vector = width_vector.clone
    vector.reverse!
    vector.length = left_offset.abs
    directions[:left_points].each do |idx|
      if (left_offset > 0)
        # Розширюємо - рухаємо назовні
        modified_points[idx] = modified_points[idx].offset(vector)
      else
        # Звужуємо - рухаємо до центру
        modified_points[idx] = modified_points[idx].offset(vector.reverse)
      end
    end
  end
  
  # Правий зсув
  if (right_offset != 0.mm)
    vector = width_vector.clone
    vector.length = right_offset.abs
    directions[:right_points].each do |idx|
      if (right_offset > 0)
        modified_points[idx] = modified_points[idx].offset(vector)
      else
        modified_points[idx] = modified_points[idx].offset(vector.reverse)
      end
    end
  end
  
  # Верхній зсув
  if (top_offset != 0.mm)
    vector = height_vector.clone
    vector.length = top_offset.abs
    directions[:top_points].each do |idx|
      if (top_offset > 0)
        modified_points[idx] = modified_points[idx].offset(vector)
      else
        modified_points[idx] = modified_points[idx].offset(vector.reverse)
      end
    end
  end
  
  # Нижній зсув
  if (bottom_offset != 0.mm)
    vector = height_vector.clone
    vector.reverse!
    vector.length = bottom_offset.abs
    directions[:bottom_points].each do |idx|
      if (bottom_offset > 0)
        modified_points[idx] = modified_points[idx].offset(vector)
      else
        modified_points[idx] = modified_points[idx].offset(vector.reverse)
      end
    end
  end
  
  modified_points
end

def apply_materials_and_attributes(group, custom_material = nil)
  return unless group
  if @wwt_attributes && !@wwt_attributes.empty?
    dict = group.attribute_dictionary('WWT', true)
    @wwt_attributes.each { |k, v| dict[k] = v unless ['userStyle', 'Normal', 'is_panel_face'].include?(k) }
  end
  # Отримуємо entities правильно залежно від типу об'єкта
  entities = group.is_a?(Sketchup::ComponentInstance) ? group.definition.entities : group.entities
  faces = entities.grep(Sketchup::Face)
  largest_faces = faces.sort_by { |face| -face.area }.first(2)
  largest_faces.each { |face| face.material = nil; face.delete_attribute('WWT', 'sidedness_type') }
  
  # Визначаємо матеріал для застосування
  material_to_apply = custom_material || @selected_material || @group_material
  
  # Перевіряємо, чи не є матеріал "Transparent"
  if material_to_apply && material_to_apply.name == "Transparent"
    material_to_apply = Sketchup.active_model.materials["Default"]
  end
  
  # Застосовуємо матеріал до граней
  (faces - largest_faces).each { |face| face.material = material_to_apply }
  
  # Застосовуємо матеріал до групи
  if custom_material || @group_material
    if (custom_material && custom_material.name == "Transparent") || 
       (@group_material && @group_material.name == "Transparent")
      group.material = Sketchup.active_model.materials["Default"]
    else
      group.material = custom_material || @group_material
    end
  end
end

def copy_texture_mapping(source_face, target_face)
  return unless source_face && target_face && @view
  material = source_face.material || source_face.back_material
  # Перевіряємо, чи не є матеріал "Transparent"
  if material && material.name == "Transparent"
    target_face.material = Sketchup.active_model.materials["Default"]
  else
    target_face.material = material
  end
end

def get_all_model_materials
  materials = Sketchup.active_model.materials
  ["За замовчуванням", "Default"] + materials.map(&:name).sort
end

def calculate_min_dimension(group)
  bounds = group.bounds
  [bounds.width, bounds.height, bounds.depth].min.to_mm.round(2)
end
      
def analyze_group_materials(group)
  return unless group
  @group_material = group.material
  # Перевіряємо, чи є матеріал групи "Transparent"
  if @group_material && @group_material.name == "Transparent"
    # Заміняємо на Default матеріал
    @group_material = Sketchup.active_model.materials["Default"]
  end
  
  # Правильно отримуємо entities залежно від типу об'єкта
  entities = if group.is_a?(Sketchup::ComponentInstance)
    group.definition.entities
  else
    group.entities
  end
  faces = entities.grep(Sketchup::Face)
  smaller_faces = faces.sort_by { |face| -face.area }[2..-1] || []
  
  # Перевіряємо матеріал граней на прозорість
  selected_mat = smaller_faces.find { |face| face.material }
  if selected_mat && selected_mat.material && selected_mat.material.name == "Transparent"
    @selected_material = Sketchup.active_model.materials["Default"]
  else
    @selected_material = selected_mat&.material
  end
  group.attribute_dictionary('WWT')&.each_pair { |k, v| @wwt_attributes[k] = v }
  faces.each do |face|
    if face.attribute_dictionary('WWT')&.[]('sidedness_type') == 'Single_sided'
      # Перевіряємо на прозорість
      if face.material && face.material.name == "Transparent"
        @wwt_attributes['single_sided_material'] = Sketchup.active_model.materials["Default"]
      else
        @wwt_attributes['single_sided_material'] = face.material
      end
      @wwt_attributes['has_single_sided'] = true
    end
  end
end

# Оновлений метод load_saved_settings для завантаження напрямкових зсувів
def load_saved_settings(model)
  dict = model.attribute_dictionary("WWT_CreatePanelArray_Settings") || {}
  { 
    default_thickness: dict["default_thickness"] || "18", 
    default_material: dict["default_material"] || "За замовчуванням", 
    group_panels: dict["group_panels"] || false,
    base_name: dict["base_name"],
    basic_dialog_width: dict["basic_dialog_width"],
    basic_dialog_height: dict["basic_dialog_height"],
    basic_dialog_left: dict["basic_dialog_left"],
    basic_dialog_top: dict["basic_dialog_top"],
    offset: dict["offset"] || "0",
    # Окремі зсуви для кожної сторони
    offset_left: dict["offset_left"] || "0",
    offset_right: dict["offset_right"] || "0",
    offset_top: dict["offset_top"] || "0",
    offset_bottom: dict["offset_bottom"] || "0",
    # Параметри для діалогу зсуву
    offset_dialog_width: dict["offset_dialog_width"] || 300,
    offset_dialog_height: dict["offset_dialog_height"] || 300,
    offset_dialog_left: dict["offset_dialog_left"] || 200,
    offset_dialog_top: dict["offset_dialog_top"] || 200
  }
end

# Створюємо узагальнений метод для збереження різних типів зсувів
def save_offsets(model, offsets_hash)
  dict = model.attribute_dictionary("WWT_CreatePanelArray_Settings", true)
  
  # Зберігаємо всі ключі/значення з хешу зсувів
  offsets_hash.each do |key, value|
    dict[key.to_s] = value
  end
  
  # Оновлюємо кеш налаштувань
  @saved_settings = load_saved_settings(model)
end

# Оновлена заміна для методів save_dimensional_offsets і save_directional_offsets
# Оновлена заміна для методів save_dimensional_offsets і save_directional_offsets
def save_settings(model, default_thickness = nil, default_material = nil, group_panels = nil, base_name = nil, offsets = nil)
  dict = model.attribute_dictionary("WWT_CreatePanelArray_Settings", true)
  dict["default_thickness"] = default_thickness if default_thickness
  dict["default_material"] = default_material if default_material
  dict["group_panels"] = group_panels unless group_panels.nil?
  dict["base_name"] = base_name if base_name
  # Зберігаємо окремі офсети для кожної сторони, якщо вони передані
  if offsets
    offsets.each do |key, value|
      dict["offset_#{key}"] = value
    end
  end
  # Оновлюємо кеш налаштувань
  @saved_settings = load_saved_settings(model)
end

# Новий метод для визначення орієнтації панелі і відповідних назв зсувів
def determine_panel_orientation
  return { is_horizontal: true, offsets: { left: "Лівий", right: "Правий", top: "Верхній", bottom: "Нижній" } } unless @face_normal
  
  # Перевіряємо нормаль грані для визначення орієнтації
  # Dot product з напрямком Z
  z_alignment = @face_normal.dot(Geom::Vector3d.new(0, 0, 1)).abs
  
  if z_alignment > 0.7
    # Горизонтальна панель (в XY площині)
    return { is_horizontal: true, offsets: { left: "Лівий", right: "Правий", top: "Верхній", bottom: "Нижній" } }
  else
    # Визначаємо, чи панель в YZ чи XZ площині
    x_alignment = @face_normal.dot(Geom::Vector3d.new(1, 0, 0)).abs
    y_alignment = @face_normal.dot(Geom::Vector3d.new(0, 1, 0)).abs
    
    if x_alignment > y_alignment
      # Панель в YZ площині (перпендикулярна до X)
      # FIXED: Corrected top/bottom labels for vertical panels
      return { is_horizontal: false, offsets: { left: "Нижній", right: "Верхній", bottom: "Лівий", top: "Правий" } }
    else
      # Панель в XZ площині (перпендикулярна до Y)
      # FIXED: Corrected top/bottom labels for vertical panels
      return { is_horizontal: false, offsets: { left: "Нижній", right: "Верхній", bottom: "Лівий", top: "Правий" } }
    end
  end
end

    end # Закриваємо клас CubTool
  end # Закриваємо модуль WWT_CreatePanelArray
end # Закриваємо модуль WWT_CreatePanelsTools

if !file_loaded?(__FILE__)
  menu = UI.menu('Plugins')
  menu.add_item('WWT_Створити масив панелей >>>') { WWT_CreatePanelsTools::WWT_CreatePanelArray.run_tool }
  file_loaded(__FILE__)
end

Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool.new)