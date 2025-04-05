# Утиліта для швидкого виправлення контекстного меню

module WWT_CreatePanelsTools
  module MenuFixer
    def self.fix_context_menu
      tool = Sketchup.active_model.tools.active_tool
      
      puts "=== Перевірка інструменту ==="
      if tool.nil?
        puts "Немає активного інструменту!"
        return false
      end
      
      puts "Активний інструмент: #{tool.class}"
      
      if tool.is_a?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
        puts "Виявлено інструмент WWT_CreatePanelArray::CubTool"
        
        # Перевірка методів
        has_rbdown = tool.respond_to?(:onRButtonDown)
        has_getmenu = tool.respond_to?(:getMenu)
        
        puts "onRButtonDown: #{has_rbdown ? 'Є' : 'Відсутній'}"
        puts "getMenu: #{has_getmenu ? 'Є' : 'Відсутній'}"
        
        if !has_rbdown || !has_getmenu
          puts "Необхідні методи відсутні, неможливо виправити!"
          return false
        end
        
        # Переконуємось, що методи публічні шляхом явного додавання
        puts "Додаємо методи onRButtonDown і getMenu, якщо вони приватні"
        
        class << tool
          # Створюємо делегації до оригінальних методів, якщо вони існують як приватні
          # або створюємо нові, якщо вони не існують взагалі
          
          public
          
          unless public_method_defined?(:onRButtonDown)
            def onRButtonDown(flags, x, y, view)
              # Простий надійний метод
              @view = view
              menu = UI::Menu.new
              getMenu(menu)
              menu.popup(x, y)
              true
            end
          end
          
          unless public_method_defined?(:getMenu)
            def getMenu(menu)
              # Простий надійний метод
              menu.add_item("Налаштування масиву панелей") do
                if valid_preview_state?
                  if @ctrl_pressed
                    show_custom_dialog_array
                  else
                    show_custom_dialog_basic
                  end
                else
                  UI.messagebox("Для налаштувань, наведіть курсор на обличку деталі")
                end
              end
              
              menu.add_separator
              
              menu.add_item("Тестове повідомлення") do
                UI.messagebox("Контекстне меню працює!")
              end
            end
          end
        end
        
        puts "Методи перевизначені як публічні"
        
        # Примусово оновлюємо інструмент
        Sketchup.active_model.tools.active_tool = tool
        
        puts "Фіксацію завершено успішно!"
        return true
      else
        puts "Активний інструмент не є WWT_CreatePanelArray::CubTool"
        return false
      end
    end
    
    def self.restart_tool
      puts "Перезапуск інструменту..."
      
      # Зберігаємо поточний стан інструменту
      was_panel_array = Sketchup.active_model.tools.active_tool.is_a?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
      
      # Вимикаємо всі інструменти
      Sketchup.active_model.select_tool(nil)
      
      # Якщо був активний наш інструмент, активуємо його знову
      if was_panel_array
        Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool.new)
        puts "Інструмент перезапущено успішно!"
      else
        puts "Інструмент масиву панелей не був активний"
      end
    end
  end
end

# Реєструємо команди для швидкого запуску
cmd_fix = UI::Command.new("Виправити контекстне меню") {
  WWT_CreatePanelsTools::MenuFixer.fix_context_menu
}

cmd_restart = UI::Command.new("Перезапустити інструмент") {
  WWT_CreatePanelsTools::MenuFixer.restart_tool
}

# Додаємо до меню
if !$menu_fixer_loaded
  menu = UI.menu("Plugins").add_submenu("WWT меню - Інструменти")
  menu.add_item(cmd_fix)
  menu.add_item(cmd_restart)
  $menu_fixer_loaded = true
end

puts "=== Інструмент виправлення меню завантажено ==="
puts "1. Запустіть інструмент масиву панелей"
puts "2. Виберіть 'Plugins > WWT меню - Інструменти > Виправити контекстне меню'"
puts "3. Спробуйте використати ПКМ на обличці деталі"
