#dev_commands args
# to do: 
#   fix: win start reset (maybe not fixed?)
#   fix: valid still not correct
#   fix: scratch on break not able to move (sets it to call)
#   make the pockets be situated better
#   make pockets part of table sprite
#       change highlighted pockets tree in call
#   create 8ball lose/win states  
#   make break feel better (or provide suggestions for break placement if issue is just hitting it dead on)
#
#   first contact must be own type
#   (temp fixed)fix scratch when table is open, but not break
#   take a look at the stuff called in cue up when movement mode == "shot" (messes with scratch) (probably resolved?)
#   see if always running call is a good idea (aka playtest)
class GTK::Controller 
    def serialize
        hello = "hello"
    end

    def inspect
        serialize.to_s
    end

    def to_s
        serialize.to_s
    end
end

def tick args
    if args.state.tick_count == 0
        puts "initialized"
        initiate args
    end
    # main game loop/conditional
    if args.state.game_started && !args.state.won
        # pause menu conditional
        if args.state.paused
            render_in_background args
            if args.state.checking_controllers
                controller_check args
            elsif args.state.switch_scratch
                choose_scratch_from_pause args
            elsif args.state.select_aim_type
                choose_aim_type args
            else
                pause_menu args
            end
        # active play conditional tree
        else
            # assign the player's controller to state.controller
            if args.state.player == 0
                args.state.controller = args.inputs.controller_one
            elsif args.state.player == 1
                args.state.controller = args.inputs.controller_two
            end

            # making the shot a called shot (shift to new turn??)
            if !(args.state.break || args.state.called_shot)
                args.state.movement_mode = "call"
                args.state.ball_chosen = false
                args.state.called_shot = true
                args.state.call_index = 0
            end

            # action conditional tree 
            
            # movement for scratch, special collision to exclude cueball
            if args.state.movement_mode == "scratch"
                scratch_movement args
                if args.state.scratch_choice == 1 || args.state.break
                    scratch_collision args
                end
                walking_collisions args
            
            # go to calling function, or special 8ball calling function if the player has no balls left
            elsif args.state.movement_mode == "call"
                player_type = (args.state.player1_type - args.state.player).abs()

                if player_type == 0 && args.state.first_stripe == 1
                    eight_ball_call args
                elsif player_type == 1 && args.state.balls[args.state.balls.length - 2][:type] != 1
                    eightball_call args
                else
                    call_shot args
                end

                collisions args

            # 
            else
                # B press
                if args.state.controller.key_down.a && !args.state.break
                    args.state.movement_mode = "call"
                    # args.state.cueball[:path] = "sprites/cueball.png" (not sure why this is here)
                    reset_sprites args
                    args.state.called_shot = true
                    args.state.ball_chosen = false
                    args.state.angle_chosen = false
                    args.state.angle_locked = false
                    args.state.call_index = 0
                elsif args.state.movement_mode == "cue"
                    cue_data = cue_up args
                end
                collisions args
            end

            # make sure valid cue data will be passed in
            cue_data ||= [0, 0, 0]

            was_moving = args.state.still_moving
            args.state.still_moving = false
            update_balls args
            # we know a new turn is when the balls (except cueball in scratch mode)
            # go from moving to stationary
            if was_moving && !args.state.still_moving
                new_turn args
            end

            render args, cue_data
            
            # Start press
            if (args.inputs.controller_one.key_down.start || args.inputs.controller_two.key_down.start)
                args.state.paused = true
            end
        end

    # win tree
    elsif args.state.won
        if args.inputs.controller_one.key_down.start || args.inputs.controller_two.key_down.start
            reset args
        end
        render_in_background args
        args.outputs.sprites << [args.state.tableleft + (args.state.table_width / 4), args.state.tablebottom + (args.state.table_height / 4), args.state.table_width / 2, args.state.table_height / 2, "sprites/win.png"]
        args.outputs.labels << [args.state.tableleft + (3 * args.state.table_width / 7), args.state.tablebottom + (args.state.table_height / 2), "Congratulations!"]
    # game start tree
    else
        render_in_background args
        choose_scratch args
    end    
end

# -----------------------------------------------------------------------------------------------------------------------------------------------------
# start up stuff

def initiate args
    #table dimensions
    args.state.table_width ||= 1100
    args.state.table_height ||= args.state.table_width / 2
    args.state.tableleft ||= (1280 - args.state.table_width) / 2
    args.state.tableright ||= args.state.tableleft + args.state.table_width
    args.state.tablebottom ||= (720 - args.state.table_height) / 2
    args.state.tabletop ||= args.state.tablebottom + args.state.table_height
    args.state.guideline_length ||= 100

    #ball info
    args.state.ball_weight ||= 5
    args.state.ball_diameter ||= 35

    #speed info
    args.state.bumpSlow ||= 0.90
    args.state.speedcap ||= 25
    args.state.max_movement ||= 4
    args.state.friction_multiplier ||= 0.99
    args.state.max_cue_power ||= args.state.speedcap

    #cueball
    args.state.cueball_start_x ||= args.state.tableleft + (args.state.table_width / 5) - args.state.ball_diameter
    args.state.cueball_start_y ||= args.state.tablebottom + (args.state.table_height / 2)
    args.state.cueball ||= {x: args.state.cueball_start_x, y: args.state.cueball_start_y, velX: 0, velY: 0, path: "sprites/cueball.png", mass: 5, type: "cueball", ball_number: 0}

    #pockets
    args.state.pocket_diameter ||= args.state.ball_diameter * (11 / 6)
    args.state.pockets ||= create_pockets args
    
    #game state
    args.state.won ||= false
    args.state.table_open ||= true
    args.state.type_set ||= false
    args.state.balls_collided ||= false
    args.state.border_bumped ||= false
    args.state.num_players ||= 2
    args.state.paused ||= false
    args.state.checking ||= []
    args.state.game_started ||= false
    args.state.player1_type ||= 0
    args.state.aim_type ||= 0

    pocketed_balls = [[], []]
    7.times do |i|
        pocketed_balls[0] << {path: "sprites/guide_ball.png", ball_number: 0}
        pocketed_balls[1] << {path: "sprites/guide_ball.png", ball_number: 0}
    end
    args.state.pocketed_balls = pocketed_balls
    args.state.pocketed_stripes = 0
    args.state.pocketed_solids = 0

    #turn state
    args.state.player ||= rand(2)
    args.state.movement_mode ||= "scratch"
    args.state.first_collision_type ||= 3
    args.state.sunk ||= false
    args.state.pocketed_this_turn ||= []
    args.state.called_shot ||= false
    args.state.successful_call ||= false
    args.state.angle_chosen ||= false
    args.state.angle_locked ||= false
    args.state.angle ||= 0
    args.state.shot_data ||= [[0, 0], 0] # [angle (unit x, unit y), power]

    #pause state
    args.state.option_select ||= 0
    args.state.checking_controllers ||= false
    args.state.switch_scratch ||= false
    args.state.select_aim_type ||= false
    args.state.pause_menu_top_coords ||= [args.state.tableleft + (args.state.table_width / 2) - 30, args.state.tabletop - (args.state.table_height / 3)]
    args.state.pause_menu_text ||= ["Resume", "Check controllers", "Choose aiming type", "Switch scratch mode", "Reset", "Testing", "Quit"]
    args.state.num_options ||= args.state.pause_menu_text.length
    args.state.scratch_options ||= ["Ball in hand", "Behind the line"]
    args.state.aim_options ||= ["Resume", "Aim as stick", "Aim as stick (inverted)", "Aim as rotation"]

    #rack triangle
    args.state.triangle_start_x ||= args.state.tableright - (args.state.table_width / 4)
    args.state.triangle_start_y ||= args.state.tabletop - (args.state.table_height / 2)
    args.state.colored_balls ||= [[1, 2, 3, 4, 5, 6, 7], [9, 10, 11, 12, 13, 14, 15]]
    create_triangle args
end

def create_pockets args
    pocket_radius = args.state.pocket_diameter / 2

    # pockets ordered clockwise topleft to bottom left <---- not sure this is correct
    pockets = [
        [args.state.tableleft - pocket_radius + 8, args.state.tabletop - pocket_radius - 8, args.state.pocket_diameter, args.state.pocket_diameter, "sprites/pocket.png"],
        [args.state.tableleft - pocket_radius + (args.state.table_width / 2), args.state.tabletop - pocket_radius + 5, args.state.pocket_diameter, args.state.pocket_diameter, "sprites/pocket.png"],
        [args.state.tableright - pocket_radius - 8, args.state.tabletop - pocket_radius - 8, args.state.pocket_diameter, args.state.pocket_diameter, "sprites/pocket.png"],
        [args.state.tableleft - pocket_radius + 8, args.state.tablebottom - pocket_radius + 8, args.state.pocket_diameter, args.state.pocket_diameter, "sprites/pocket.png"],
        [args.state.tableleft - pocket_radius + (args.state.table_width / 2), args.state.tablebottom - pocket_radius - 5, args.state.pocket_diameter, args.state.pocket_diameter, "sprites/pocket.png"],
        [args.state.tableright - pocket_radius - 8, args.state.tablebottom - pocket_radius + 8, args.state.pocket_diameter, args.state.pocket_diameter, "sprites/pocket.png"]
    ]

    return pockets
end

def create_triangle args

    # create variables to be used in the loop
    # eigthball initialized here so it can be added at the end of the balls list later
    balls = [args.state.cueball, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    start_x = args.state.triangle_start_x
    start_y = args.state.triangle_start_y
    ball_diameter = args.state.ball_diameter
    ball_radius = ball_diameter / 2
    eightball = 1

    # go column by column. First ball in each column is bottom ball
    # color alternates except for two special cases (8 ball and 2nd ball in last column)
    (0..4).each do |i|
        color = i % 2
        # all balls in a column have the same start point
        x_offshift = ball_diameter * i
        y_offshift = -ball_radius * i
        (0..i).each do |j|
            # number of balls in that group (used to randomize placement)
            num_colors = args.state.colored_balls[color].length - 1
            if i == 2 && j == 1
                balls[8] = {x: start_x + x_offshift,
                y: start_y + y_offshift + (ball_diameter * j),
                velX: 0,
                velY: 0,
                path: "sprites/ball8.png",
                mass: args.state.ball_weight,
                type: 8,
                ball_number: 8
                }
            # do not alternate color on the second ball in the last column
            elsif i == 4 && j == 1
                # choose ball number
                index = rand(args.state.colored_balls[color].length)
                number = args.state.colored_balls[color][index]

                balls[number] = {x: start_x + x_offshift,
                y: start_y + y_offshift + (ball_diameter * j),
                velX: 0,
                velY: 0,
                path: "sprites/ball#{number}.png",
                mass: args.state.ball_weight,
                type: color,
                ball_number: number
                }
                # remove the number from the available list
                args.state.colored_balls[color].delete_at(index)
            else
                # choose a random ball from the color group (solid/stripes)
                index = rand(args.state.colored_balls[color].length)
                number = args.state.colored_balls[color][index]

                balls[number] = {x: start_x + x_offshift,
                y: start_y + y_offshift + (ball_diameter * j),
                velX: 0,
                velY: 0,
                path: "sprites/ball#{number}.png",
                mass: args.state.ball_weight,
                type: color,
                ball_number: number
                }

                # remove the number from the available list and change ball type
                args.state.colored_balls[color].delete_at(index)
                color = (color + 1) % 2
            end
        end
    end

    # these are the indecies for the first ball of each ball group in args.state.balls
    args.state.first_solid = 1
    args.state.first_stripe = 9
    args.state.balls = balls
end

# -----------------------------------------------------------------------------------------------------------------------------
# menu stuff

def choose_scratch args
    option_num = args.state.option_select

    # render white background to highlight the current option
    text_length = args.state.scratch_options[option_num].length()
    args.outputs.solids << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * (option_num + 1)), 10 * text_length, 20, 255, 255, 255]

    # render the scratch rules options
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] + 40, "Choose scratch rules"]
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1], "Ball in hand"]
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - 20, "Behind the line"]

    # render description of the rule highlighted
    if option_num == 0
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 130, args.state.pause_menu_top_coords[1] - 60, "A scratched ball can be placed anywhere."]
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 230, args.state.pause_menu_top_coords[1] - 80, "A scratched ball is a penalty for the player who scratched."]
    else
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 180, args.state.pause_menu_top_coords[1] - 60, "A scratched ball must be placed behind the baulk line."]
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 130, args.state.pause_menu_top_coords[1] - 80, "A scratched ball may be a strategic option."]
    end

    # Direction press
    if args.inputs.controller_one.key_down.down || args.inputs.controller_two.key_down.down
        args.state.option_select = (option_num + 1) % 2
    elsif args.inputs.controller_one.key_down.up || args.inputs.controller_two.key_down.up
        args.state.option_select = (option_num - 1) % 2
    end

    # A press
    # select the currently highlighted option and begin the game in break mode
    if args.inputs.controller_one.key_down.b || args.inputs.controller_two.key_down.b
        args.state.scratch_choice = option_num
        args.state.game_started = true
        args.state.break = true
    end
end

def pause_menu args
    option_num = args.state.option_select
    num_options = args.state.num_options

    # white background to highlight the current option
    text_length = args.state.pause_menu_text[option_num].length()
    args.outputs.solids << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * (option_num + 1)), 10 * text_length, 20, 255, 255, 255]
    
    # Direction press
    if args.inputs.controller_one.key_down.down || args.inputs.controller_two.key_down.down
        args.state.option_select = (option_num + 1) % num_options
    elsif args.inputs.controller_one.key_down.up || args.inputs.controller_two.key_down.up
        args.state.option_select = (option_num - 1) % num_options
    end

    # menu text
    args.state.pause_menu_text.each_with_index do |text, n|
        args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * n), text]
    end

    # A press
    # case based on enlgish phrases for readability (not much loss to speed because run infrequently)
    if args.inputs.controller_one.key_down.b || args.inputs.controller_two.key_down.b
        case args.state.pause_menu_text[option_num]
        when "Resume"
            args.state.paused = false
            args.state.option_select = 0
        when "Check controllers"
            args.state.checking_controllers = true
            args.state.option_select = 0
        when "Switch scratch mode"
            args.state.switch_scratch = true
            args.state.option_select = 0
        when "Choose aiming type"
            args.state.select_aim_type = true
            args.state.option_select = 0
        when "Reset"
            reset args
            args.state.option_select = 0
            args.state.paused = false
        when "Testing"
            args.state.cueball[:x] = args.state.tableright - 100
            args.state.cueball[:y] = args.state.tabletop
            args.state.balls = [args.state.cueball]
            args.state.num_collisions = 0
            new_ball1 args
            new_ball2 args
        when "Quit"
            puts "lol trying to quit"
        end
    end
end

def choose_scratch_from_pause args
    option_num = args.state.option_select

    # white background to highlight the current option
    text_length = args.state.scratch_options[option_num - 1].length()
    args.outputs.solids << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * (option_num + 1)), 10 * text_length, 20, 255, 255, 255]

    # render the options
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1], "Resume"]
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - 20, "Ball in hand"]
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - 40, "Behind the line"]

    # render the descriptions of the scratch rules
    if option_num == 1
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 130, args.state.pause_menu_top_coords[1] - 80, "A scratched ball can be placed anywhere."]
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 230, args.state.pause_menu_top_coords[1] - 100, "A scratched ball is a penalty for the player who scratched."]
    elsif option_num == 2
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 180, args.state.pause_menu_top_coords[1] - 80, "A scratched ball must be placed behind the baulk line."]
        args.outputs.labels << [args.state.pause_menu_top_coords[0] - 130, args.state.pause_menu_top_coords[1] - 100, "A scratched ball may be a strategic option."]
    end

    # Direction press
    if args.inputs.controller_one.key_down.down || args.inputs.controller_two.key_down.down
        args.state.option_select = (option_num + 1) % 3
    elsif args.inputs.controller_one.key_down.up || args.inputs.controller_two.key_down.up
        args.state.option_select = (option_num - 1) % 3
    end

    # A press
    if (args.inputs.controller_one.key_down.b || args.inputs.controller_two.key_down.b)
        if option_num > 0
            args.state.scratch_choice = option_num - 1 
            args.state.switch_scratch = false
        else
            args.state.switch_scratch = false
        end
    end
end

def choose_aim_type args
    option_num = args.state.option_select

    # white background to highlight the current option
    text_length = args.state.aim_options[option_num].length()
    args.outputs.solids << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * (option_num + 1)), 10 * text_length, 20, 255, 255, 255]

    # render the options
    args.state.aim_options.each_with_index do |text, i|
        args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * i), text]
    end

    # Direction press
    if args.inputs.controller_one.key_down.down || args.inputs.controller_two.key_down.down
        args.state.option_select = (option_num + 1) % (args.state.aim_options.length)
    elsif args.inputs.controller_one.key_down.up || args.inputs.controller_two.key_down.up
        args.state.option_select = (option_num - 1) % (args.state.aim_options.length)
    end

    # A press
    if (args.inputs.controller_one.key_down.b || args.inputs.controller_two.key_down.b)
        if option_num > 0
            args.state.aim_type = option_num - 1 
            args.state.select_aim_type = false
        else
            args.state.select_aim_type = false
        end
    end
end

# menu to check which controller is 1 or 2 / that the controllers are working
def controller_check args

    option_num = args.state.option_select

    # white background to highlight the current option
    args.outputs.solids << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * (option_num + 1)), 10 * 6, 20, 255, 255, 255]
    args.outputs.labels << [args.state.pause_menu_top_coords[0], args.state.pause_menu_top_coords[1] - (20 * (option_num)), "Return"]
    
    # A press
    if args.inputs.controller_one.key_down.b || args.inputs.controller_one.key_down.b
        args.state.option_select = 0
        args.state.checking_controllers = false
    end

    args.outputs.labels << [args.state.tableleft + 100, args.state.tabletop + 20, "Now press B... "]

    # B pres
    # when the b button is pressed on a controller, show which controller pressed the button
    if args.inputs.controller_one.key_held.a
        args.outputs.labels << [args.state.tableleft + 250, args.state.tabletop + 20, "controller 1: pressed"]
    end
    if args.inputs.controller_two.key_held.a
        args.outputs.labels << [args.state.tableleft + 700, args.state.tabletop + 20, "controller 2: pressed"]
    end
end



# --------------------------------------------------------------------------------------------------------------------------------------------
# calling stuff

# selecting the ball and pocket to call
def call_shot args
    item = args.state.call_index

    # selecting pocket conditional tree
    if args.state.ball_chosen
        pocket = args.state.pockets[item]
        # set the pocket's image to the highlighted version of pocket
        pocket[4] = "sprites/highlighted_pocket.png"

        # change pocket
        # Direction press
        if args.state.controller.key_down.right
            pocket[4] = "sprites/pocket.png"
            # ignore the "if" if it feels non-intuitive
            if !(item == 2 || item == 5)
            #     args.state.call_index = (args.state.call_index + 3) % args.state.pockets.length
            # else
                args.state.call_index = (args.state.call_index + 1) % args.state.pockets.length
            end
        # Direction press
        elsif args.state.controller.key_down.left
            pocket[4] = "sprites/pocket.png"
            # ignore the "if" if it feels non-intuitive
            if !(item == 0 || item == 3)
            #     args.state.call_index = (args.state.call_index + 3) % args.state.pockets.length
            # else
                args.state.call_index = (args.state.call_index - 1) % args.state.pockets.length
            end
        # Direction press
        elsif args.state.controller.key_down.up || args.state.controller.key_down.down
            pocket[4] = "sprites/pocket.png"
            args.state.call_index = (args.state.call_index + 3) % args.state.pockets.length
        end

        # A press
        # select pocket and start cueing up
        if args.state.controller.key_down.b
            args.state.called_pocket = pocket
            args.state.movement_mode = "cue"
            args.state.successful_call = false
        end

        # B press
        # reset pocket and go back to choosing ball
        if args.state.controller.key_down.a
            pocket[4] = "sprites/pocket.png"
            args.state.call_index = 0
            args.state.ball_chosen = false
            called_ball = args.state.called_ball
            called_ball[1][:path] = "sprites/ball#{called_ball[0]}.png"
        end

    # selecting ball
    else
        # only look at the current player's group
        if (args.state.player == 0 && args.state.player1_type == 0) || (args.state.player == 1 && args.state.player1_type == 1)
            current_ball = args.state.balls[1 + item]
        else 
            current_ball = args.state.balls[args.state.first_stripe + item]
        end

        number = current_ball[:ball_number]
        image = current_ball[:path]

        # replace this ball's image with the highlighted version
        if !(image == "sprites/highlighted_ball#{number}.png")
            args.state.ball_image = number
            current_ball[:path] = "sprites/highlighted_ball#{number}.png" 
        else
            # Direction press
            # change ball
            if args.state.controller.key_down.right
                # return the current_ball to its original image
                current_ball[:path] = "sprites/ball#{args.state.ball_image}.png"
                # go to the next ball
                if (args.state.player == 0 && args.state.player1_type == 0) || (args.state.player == 1 && args.state.player1_type == 1)
                    args.state.call_index = (args.state.call_index + 1) % (7 - args.state.pocketed_solids)
                else
                    args.state.call_index = (args.state.call_index + 1) % (7 - args.state.pocketed_stripes)
                end

            # Direction press
            elsif args.state.controller.key_down.left
                # return the current_ball to its original image
                current_ball[:path] = "sprites/ball#{args.state.ball_image}.png"
                # go to the next ball
                if (args.state.player == 0 && args.state.player1_type == 0) || (args.state.player == 1 && args.state.player1_type == 1)
                    args.state.call_index =(args.state.call_index - 1) % (7 - args.state.pocketed_solids)
                else
                    args.state.call_index = (args.state.call_index - 1) % (7 - args.state.pocketed_stripes)
                end
            end

            # R1 press L1 press
            # if table open, switch ball group (by changing first player's group)
            if args.state.table_open
                if args.state.controller.key_down.r1 || args.state.controller.key_down.l1
                    args.state.player1_type = 1 - args.state.player1_type
                    current_ball[:path] = "sprites/ball#{args.state.ball_image}.png"
                end
            end

            # A press
            # select ball (store its original image to bring it back to normal)
            if args.state.controller.key_down.b
                args.state.called_ball = [number, current_ball]
                args.state.ball_chosen = true
                args.state.call_index = 0
            end
        end
    end
end


def eightball_call args
    item = args.state.call_index

    pocket = args.state.pockets[item]
    # set the pocket's image to the highlighted version of pocket
    pocket[4] = "sprites/highlighted_pocket.png"

    # change pocket
    # Direction press
    if args.state.controller.key_down.right
        pocket[4] = "sprites/pocket.png"
        if !(item == 2 || item == 5)
            args.state.call_index = (args.state.call_index + 1) % args.state.pockets.length
        end
    # Direction press
    elsif args.state.controller.key_down.left
        pocket[4] = "sprites/pocket.png"
        if !(item == 0 || item == 3)
            args.state.call_index = (args.state.call_index - 1) % args.state.pockets.length
        end
    # Direction press
    elsif args.state.controller.key_down.up || args.state.controller.key_down.down
        pocket[4] = "sprites/pocket.png"
        args.state.call_index = (args.state.call_index + 3) % args.state.pockets.length
    end

    # A press
    # select pocket and start cueing up
    if args.state.controller.key_down.b
        args.state.called_pocket = pocket
        args.state.movement_mode = "cue"
        args.state.successful_call = false
    end
end

# ---------------------------------------------------------------------------------------------------------------------------------------
# scratch related stuff

def scratch_movement args
    # Left Stick movement
    x_raw = args.state.controller.left_analog_x_raw
    y_raw = args.state.controller.left_analog_y_raw
    
    move_vector = (x_raw ** 2) + (y_raw ** 2)

    if move_vector != 0
        # get unit vector for diraction to apply movement
        unit_x = x_raw / (move_vector ** (1 / 2))
        unit_y = y_raw / (move_vector ** (1 / 2))
        # used for debugging (should be 1)
        mag_unit = (unit_x ** 2) + (unit_y ** 2)

        # make power of move proportional to size of vector (make it proportional to its greatest x or y raw)
        if x_raw.abs() > y_raw.abs()
            move = args.state.max_movement * (x_raw.abs() / 32000)
        else
            move = args.state.max_movement * (y_raw.abs() / 32000)
        end

        if args.state.cueball[:velX].abs() < args.state.max_movement
            args.state.cueball[:velX] = move * unit_x
        end
        if args.state.cueball[:velY].abs() < args.state.max_movement
            args.state.cueball[:velY] = move * unit_y    
        end
    else 
        args.state.cueball[:velX] = 0
        args.state.cueball[:velY] = 0
    end

    # L2 press
    # change to cue mode
    if args.state.controller.key_down.l2 && !args.state.still_moving
        valid = valid_spot args
        if valid
            args.state.movement_mode = "cue"
            args.state.cueball[:path] = "sprites/cueball.png"
            args.state.cueball[:velX] = 0
            args.state.cueball[:velY] = 0
            args.state.called_shot = false
        end
    end
end

# make sure the cueball isn't in a pocket or another ball when placing
def valid_spot args
    ball_center_x = args.state.cueball[:x] + (args.state.ball_diameter / 2)
    ball_center_y = args.state.cueball[:y] + (args.state.ball_diameter / 2)
    pocket_radius = args.state.pocket_diameter / 2

    # if you can place anywhere, check each pocket, else, just check left two pockets
    if args.state.scratch_choice == 0
        args.state.pockets.each do |pocket|
            dist = (((ball_center_x - pocket[0]) ** 2) + ((ball_center_y - pocket[1]) ** 2)) ** (1/2)
            if dist <= pocket_radius
                return false
            end
        end
    else
        dist_to_bottom = (((ball_center_x - args.state.tableleft) ** 2) + ((ball_center_y - args.state.tablebottom) ** 2)) ** (1/2)
        dist_to_top = (((ball_center_x - args.state.tableleft) ** 2) + ((ball_center_y - args.state.tabletop) ** 2)) ** (1/2)
        if dist_to_bottom < pocket_radius || dist_to_top < pocket_radius
            return false
        end
    end

    # check each ball on the table
    num_balls = args.state.balls.length
    ball1 = args.state.balls[0]
    (1..num_balls - 1).each do |j|
        ball2 = args.state.balls[j]
        dist = (((ball1[:x] - ball2[:x]) ** 2) + ((ball1[:y] - ball2[:y]) ** 2)) ** (1/2)
        if dist < args.state.ball_diameter
            return false
        end
    end
    return true
end

# ------------------------------------------------------------------------------------------------------------------------------
# cue related stuff

#handles the ball in cue state
def cue_up args
    
    #make the shot if in cue mode
    if args.state.angle_chosen
        return power args
    elsif args.state.aim_type == 2
        return rotation_angle args
    elsif args.state.angle_locked
        return fine_angle_adjustment args
    else
        return choose_angle args
    end
end

def power args
    controller = args.state.controller
    x_raw = controller.left_analog_x_raw
    y_raw = controller.left_analog_y_raw

    # R2 press
    shot = controller.key_down.r2

    cue_vector = (x_raw ** 2) + (y_raw ** 2)
    if controller.key_down.l2
        args.state.angle_chosen = false
    elsif cue_vector != 0

        unit_x = Math.cos(args.state.angle)
        unit_y = Math.sin(args.state.angle)

        # make power of shot proportional to size of vector (make it proportional to its greatest x or y raw)
        if x_raw.abs() > y_raw.abs()
            power = args.state.max_cue_power  * (x_raw.abs() / 32000)
        else
            power = args.state.max_cue_power * (y_raw.abs() / 32000)
        end

        # make the shot if right trigger pressed
        if shot
            args.state.cueball[:velX] -= power * unit_x
            args.state.cueball[:velY] -= power * unit_y
            args.state.movement_mode = "shot"
            args.state.sunk = false
            args.outputs.sounds << "sounds/cue_hit.wav"
        end
        return [unit_x, unit_y, power]
    else
        return [Math.cos(args.state.angle), Math.sin(args.state.angle), 0]
    end
end

def rotation_angle args
    controller = args.state.controller

    if controller.key_held.x
        if controller.key_held.l1
            args.state.angle += 0.001
        elsif controller.key_held.r1
            args.state.angle -= 0.001
        end
    else
        if controller.key_held.l1
            args.state.angle += 0.02
        elsif controller.key_held.r1
            args.state.angle -= 0.02
        end
    end

    if controller.key_down.r2
        args.state.angle_chosen = true
    end

    return [Math.cos(args.state.angle), Math.sin(args.state.angle), 10]
end


def fine_angle_adjustment args
    controller = args.state.controller

    if !controller.key_held.r2
        if controller.key_held.left
            args.state.angle += 0.001
        elsif controller.key_held.right
            args.state.angle -= 0.001
        end
    end
    
    # go back to choosing angle
    if controller.key_down.l2
        args.state.angle_locked = false
    end

    if controller.key_down.r2
        args.state.angle_chosen = true
    end

    return [Math.cos(args.state.angle), Math.sin(args.state.angle), 10]
end

def choose_angle args
    x_raw = args.state.controller.left_analog_x_raw
    y_raw = args.state.controller.left_analog_y_raw
    lock_in = args.state.controller.key_down.r2
    cue_vector = (x_raw ** 2) + (y_raw ** 2)

    
    if cue_vector == 0
        return [0, 0, 0]
    else
        # get unit vector for diraction to apply power
        unit_x = x_raw / (cue_vector ** (1 / 2))
        unit_y = y_raw / (cue_vector ** (1 / 2))

        if args.state.aim_type == 1
            unit_x = -unit_x
            unit_y = -unit_y
        end

        # L2 press
        if lock_in
            args.state.angle_locked = true
            if unit_y > 0
                args.state.angle = Math.acos(unit_x)
            else
                args.state.angle = -1 * Math.acos(unit_x)
            end
        end

        return [unit_x, unit_y, 10]
    end
end

# this is the old way of cue shot, where angle and power done in same motion, and shot is right hand
# R2 press, Right Stick movement
def cue_shot args
    x_raw = args.state.controller.right_analog_x_raw
    y_raw = args.state.controller.right_analog_y_raw

    # R2 press
    shot = args.state.controller.key_down.r2

    cue_vector = (x_raw ** 2) + (y_raw ** 2)
    if cue_vector != 0

        # get unit vector for diraction to apply power
        unit_x = x_raw / (cue_vector ** (1 / 2))
        unit_y = y_raw / (cue_vector ** (1 / 2))
        # used for debugging
        mag_unit = (unit_x ** 2) + (unit_y ** 2)

        # make power of shot proportional to size of vector (make it proportional to its greatest x or y raw)
        if x_raw.abs() > y_raw.abs()
            power = args.state.max_cue_power  * (x_raw.abs() / 32000)
        else
            power = args.state.max_cue_power * (y_raw.abs() / 32000)
        end

        # make the shot if right trigger pressed
        if shot
            args.state.cueball[:velX] -= power * unit_x
            args.state.cueball[:velY] -= power * unit_y
            args.state.movement_mode = "shot"
            args.state.cueball[:path] = "sprites/cueball.png"
            args.state.sunk = false
            args.outputs.sounds << "sounds/cue_hit.wav"
        end

        return [unit_x, unit_y, power]
    else
        if shot
            args.state.movement_mode = "cue"
            args.state.cueball[:path] = "sprites/cueball.png"
        end
        return [0, 0, 0]
    end
end

# ----------------------------------------------------------------------------------------------------------------------------------------
# rendering stuff

def render args, cue_data

    # pool table 
    args.outputs.solids << [args.state.tableleft, args.state.tablebottom, args.state.table_width, args.state.table_height, 0, 150, 0]

    # pockets
    args.state.pockets.each do |pocket|
        args.outputs.sprites << pocket
    end

    # baulk line
    args.outputs.lines << [args.state.tableleft + (args.state.table_width / 5),
        args.state.tabletop,
        args.state.tableleft + (args.state.table_width / 5),
        args.state.tablebottom,
        255, 
        255,
        255
    ]
    
    # pocketed balls and their container
    left_bound = args.state.tableleft + 100
    bottom_bound = args.state.tabletop + 25
    ball_diameter = args.state.ball_diameter
    if args.state.type_set
        render_pocketed_balls args, left_bound, bottom_bound, ball_diameter
    else
        render_waiting_balls args
        # args.outputs.borders << [left_bound, bottom_bound, ball_diameter * 7, ball_diameter]
        # args.outputs.borders << [left_bound + 600, bottom_bound, ball_diameter * 7, ball_diameter]
    end

    # cue and guide line
    if args.state.movement_mode == "cue"
        render_cue args, cue_data
    end

    

    # pool balls
    args.state.balls.each do |ball|
        if ball != 0
            args.outputs.sprites << [ball[:x], ball[:y], args.state.ball_diameter, args.state.ball_diameter, ball[:path]]
        end
    end

    # if args.state.movement_mode != "scratch"
    if args.state.still_moving
        if args.state.balls_collided && args.state.tick_count % 5 == 0 
            args.outputs.sounds << "sounds/ball_clank.wav"
            args.state.balls_collided = false
        end
        if args.state.border_bumped && args.state.tick_count % 5 == 0
            args.outputs.sounds << "sounds/avg_border_bump.wav"
            args.state.border_bumped = false
        end
    else
        args.state.balls_collided = false
        args.state.border_bumped = false
    end

    # debugging info
    # args.outputs.labels << [100, 150, "x stick: #{args.state.controller.left_analog_x_raw} y stick: #{args.state.controller.left_analog_y_raw}"]
    # if args.state.balls.length > 2
    #     ball1 = args.state.balls[1]
    #     ball2 = args.state.balls[2]
    #     distance = (((ball1[:x] - ball2[:x]) ** 2) + (ball1[:y] - ball2[:y]) ** 2) ** (1 / 2)
    #     args.outputs.labels << [100, 180, "distance: #{distance}"]
    #     args.outputs.labels << [100, 200 , "diameter: #{ball_diameter}"]
    #     x = 200 - ((10 / (200 ** (1 / 2))) * args.state.ball_diameter) + (ball_diameter / 2)
    #     y = 250 + ((-10 / (200 ** (1 / 2))) * args.state.ball_diameter) + 2 + (ball_diameter / 2)
    #     args.outputs.lines << [x + 100, y - 100, x - 100, y + 100]
    #     normal_x = (ball1[:x] - ball2[:x]) / distance
    #     normal_y = (ball1[:y] - ball2[:y]) / distance
    #     args.outputs.lines << [ball1[:x] + (200 * normal_x) + (ball_diameter / 2), ball1[:y] + (200 * normal_y) + (ball_diameter / 2), ball2[:x] - (200 * normal_x) + (ball_diameter / 2), ball2[:y] - (200 * normal_y) + (ball_diameter / 2), 255, 0, 0]
    # end
    # args.state.num_collisions ||= 0
    # args.outputs.labels << [args.state.tableright - 80, 140, "Collisions: #{args.state.num_collisions}"]
    # if args.state.type_set
    #     args.state.balls.each_with_index do |ball, i|
    #         if i == 0
    #             args.outputs.labels << [180, 120, "c"]
    #         else
    #         args.outputs.labels << [180 + (20 * i), 120, ball[:type]]
    #         end
    #     end
    #     args.outputs.labels << [200, 100, args.state.first_stripe]
    # end
    # args.outputs.labels << [180, 100, args.state.movement_mode]
    # args.outputs.labels << [100, 120, "right x: #{args.inputs.controller_one.right_analog_x_raw} right y: #{args.inputs.controller_one.right_analog_y_raw}"]
    # args.outputs.labels << [100, 140, "left x: #{args.inputs.controller_one.left_analog_x_raw} left y: #{args.inputs.controller_one.left_analog_y_raw}"]
end

def render_pocketed_balls args, left_bound, bottom_bound, ball_diameter
    pocketed_balls = args.state.pocketed_balls

    # player 1's balls
    # args.outputs.borders << [left_bound, bottom_bound, ball_diameter * 7, ball_diameter]
    pocketed_balls[args.state.player1_type].each_with_index do |ball, n|
        args.outputs.sprites << [left_bound + (n * ball_diameter), bottom_bound, ball_diameter, ball_diameter, ball[:path]]
    end
    
    # player 2's balls
    left_bound += 600
    # args.outputs.borders << [left_bound, bottom_bound, ball_diameter * 7, ball_diameter]
    pocketed_balls[1 - args.state.player1_type].each_with_index do |ball ,n|
        args.outputs.sprites << [left_bound + (n * ball_diameter), bottom_bound, ball_diameter, ball_diameter, ball[:path]]
    end
end

def render_cue args, cue_data
    # fix: change to cue_data[0][i] same for power below
    unit_x = cue_data[0]
    unit_y = cue_data[1]

    # get the sign/direction of unit_y (1 or -1)
    if unit_y != 0
        sign_unit_y = unit_y.abs() / unit_y
    else
        sign_unit_y = 1
    end

    # fix: change to cue_datta[1]
    power = cue_data[2]
    ball_diameter = args.state.ball_diameter

    # find rotation angle (in radians) using the unit cue vector and <1, 0>
    angle = Math.acos(unit_x)

    # convert radians to degrees
    angle = angle * (180 / Math.acos(-1))
    angle = 0 if unit_x == 0 && unit_y == 0

    ball_center_x = args.state.cueball[:x] + (ball_diameter / 2)
    ball_center_y = args.state.cueball[:y] + (ball_diameter / 2)

    # offset to render tip at center
    to_edge = ball_diameter / 2
    power_offset = 100 * (power / args.state.max_cue_power)
    angle_offset_x = (power_offset + to_edge) * unit_x
    angle_offset_y = (power_offset + to_edge) * unit_y
    # check if commenting this out breaks the code
    # if power == 0
    #     angle_offset_x = to_edge
    # end

    # used hash because we need to set rotation point
    cue = {
        x: ball_center_x + angle_offset_x,
        y: ball_center_y + angle_offset_y - 12,
        w: 400,
        h: 25, 
        path:"sprites/cue.png",
        angle: angle * sign_unit_y,
        angle_anchor_x: 0,
        angle_anchor_y: 0.5,
    }
    args.outputs.sprites << cue

    # render guide
    if unit_x.abs() < 0.001
        render_guide_inverted args, unit_x, unit_y, ball_center_x, ball_center_y, ball_diameter
    else
        render_guide args, unit_x, unit_y, ball_center_x, ball_center_y, ball_diameter
    end

    
    # render power output
    if args.state.angle_chosen
        args.outputs.borders << [20, 150, 40, 400]
        args.outputs.solids << [20, 150, 40, 400 * (power / args.state.max_cue_power), 255, 0, 0]
    end
end

def render_guide args, unit_x, unit_y, cueball_center_x, cueball_center_y, ball_diameter
    slope = unit_y / unit_x
    sign_unit_x = unit_x / unit_x.abs()
    sign_unit_y = unit_y / unit_y.abs()
    closest_dist = 100000
    closest_x = false
    closest_y = false
    closest_ball_x = false
    closest_ball_y = false

    # we know if ball is in path, at some x,y the center of the guide is ball_diameter away from the ball_x and ball_y
    # (ball_x - x)^2 + (ball_y - y)^2 = ball_diameter^2
    # Also we know that same x,y solves the line drawn from the cueball center along the slope.
    

    # Thus y = (slope * x) - (slope * cueball_x) + cueball_y
    # Plugging in (slope * x) - (slope * cueball_x) + cueball_y for y in the first equation, we can solve for x.
    # It comes down to the quadratic formula giving us two x's which we can plug back into 
    # y = (slope * x) - (slope * cueball_x) + cueball_y to get y.
    # Whichever x,y pair is closest to the cueball is where the guide ball center is.
    
    # if b^2 - 4ac < 0, skip because that will fuck shit up

    # the y intercept of y = (slope * x) - (slope * cueball_x) + cueball_y
    y_int = cueball_center_y - (slope * cueball_center_x)
    ball_diameter_sqrd = ball_diameter ** 2 - 1

    # "a" of the quadratic formula does not depend on the other ball
    a = (slope ** 2) + 1

    args.state.balls.each_with_index do |ball, i|
        if i != 0
            # get the center of the other ball
            ball_x = ball[:x] + (ball_diameter / 2)
            ball_y = ball[:y] + (ball_diameter / 2)
            distance_to_ball = ((ball_x - cueball_center_x) ** 2 + (ball_y - cueball_center_y) ** 2) ** (1 / 2)

            ball_unit_x = (cueball_center_x - ball_x) / distance_to_ball
            if ball_unit_x == 0
                sign_ball_x = 1
            else
                sign_ball_x = ball_unit_x / ball_unit_x.abs()
            end

            ball_unit_y = (cueball_center_y - ball_y) / distance_to_ball
            if ball_unit_y == 0
               sign_ball_y = 1 
            else
                sign_ball_y = ball_unit_y / ball_unit_y.abs()
            end

            if sign_ball_y == sign_unit_y || sign_ball_x == sign_unit_x
                b = -2 * (ball_x + (slope * (ball_y - y_int)))
                c = (ball_x ** 2)  + ((ball_y - y_int) ** 2) - ball_diameter_sqrd
                discriminant = (b ** 2) - (4 * a * c)
                if discriminant >= 0
                    # ball[:path] = "sprites/highlighted_pocket.png"
                    guide_x1 = (-b + (discriminant ** (1 / 2))) / (2 * a)
                    guide_y1 = (slope * guide_x1) + y_int
                    distance1 = ((guide_x1 - cueball_center_x) ** 2 + (guide_y1 - cueball_center_y) ** 2)

                    guide_x2 = (-(discriminant ** (1 / 2)) - b) / (2 * a)
                    guide_y2 = (slope * guide_x2) + y_int
                    distance2 = ((guide_x2 - cueball_center_x) ** 2 + (guide_y2 - cueball_center_y) ** 2)

                    if distance1 < distance2
                        distance1 = distance1 ** (1 / 2)
                        if distance1 <= closest_dist
                            sign_guide_x = (cueball_center_x - guide_x1) / (cueball_center_x - guide_x1).abs()

                            # preventing divide by zero error
                            if (cueball_center_y - guide_y1) == 0
                                # this will only happen when the slope is very, very small (unit_y < 0.00001), so the signs should match
                                sign_guide_y = sign_unit_y
                            else
                                sign_guide_y = (cueball_center_y - guide_y1) / (cueball_center_y - guide_y1).abs()
                            end
                            
                            if (sign_guide_y == sign_unit_y || unit_y == 0) && sign_guide_x == sign_unit_x
                                closest_dist = distance1
                                closest_x = guide_x1
                                closest_y = guide_y1
                                closest_ball_x = ball_x
                                closest_ball_y = ball_y
                            end
                        end
                    else
                        distance2 = distance2 ** (1 / 2)
                        if distance2 <= closest_dist
                            sign_guide_x = (cueball_center_x - guide_x2) / (cueball_center_x - guide_x2).abs()
                            sign_guide_y = (cueball_center_y - guide_y2) / (cueball_center_y - guide_y2).abs()
                            if (sign_guide_y == sign_unit_y || unit_y == 0) && sign_guide_x == sign_unit_x
                                closest_dist = distance2
                                closest_x = guide_x2
                                closest_y = guide_y2
                                closest_ball_x = ball_x
                                closest_ball_y = ball_y
                            end
                        end
                    end
                # else
                #     ball[:path] = "sprites/ball2.png"
                end
            # else
            #     ball[:path] = "sprites/ball3.png"
            end
        end
    end

    ball_radius = ball_diameter / 2
    left = args.state.tableleft
    right = args.state.tableright
    bottom = args.state.tablebottom
    top = args.state.tabletop

    if closest_x
        if !(closest_x > left + ball_radius && closest_x < right - ball_radius && closest_y > bottom + ball_radius && closest_y < top - ball_radius)
            render_guide_at_border args, unit_x, unit_y, cueball_center_x, cueball_center_y, slope, y_int, ball_diameter, left, right, bottom, top
        else
            dist = (((closest_ball_x - closest_x) ** 2) - ((closest_ball_y - closest_y) ** 2)) ** (1 / 2)
            nuvx = (closest_ball_x - closest_x) / dist
            nuvy = (closest_ball_y - closest_y) / dist

            args.outputs.lines << [cueball_center_x, cueball_center_y, closest_x + (ball_diameter * unit_x / 2), closest_y + (ball_diameter * unit_y / 2)]
            # args.outputs.lines << [cueball_center_x, cueball_center_y, closest_ball_x, closest_ball_y, 0 , 0, 255]
            if nuvx != unit_y && nuvy != -unit_x
                args.outputs.sprites << [closest_x - (ball_diameter / 2), closest_y - (ball_diameter / 2), ball_diameter, ball_diameter, "sprites/guide_ball.png"]
            end
        end
    else
        render_guide_at_border args, unit_x, unit_y, cueball_center_x, cueball_center_y, slope, y_int, ball_diameter, left, right, bottom, top
    #     args.outputs.lines << [cueball_center_x, cueball_center_y, cueball_center_x - (500 * unit_x), cueball_center_y - (500 * unit_y), 255, 0, 0]
    end

end


def render_guide_inverted args, unit_x, unit_y, cueball_center_x, cueball_center_y, ball_diameter
    slope = unit_x / unit_y
    sign_unit_y = unit_y / unit_y.abs()
    closest_dist = 100000
    closest_x = false
    closest_y = false
    closest_ball_x = false
    closest_ball_y = false

    # the y intercept of y = (slope * x) - (slope * cueball_x) + cueball_y
    x_int = cueball_center_x - (slope * cueball_center_y)
    ball_diameter_sqrd = ball_diameter ** 2 - 1

    # "a" of the quadratic formula does not depend on the other ball
    a = (slope ** 2) + 1

    args.state.balls.each_with_index do |ball, i|
        if i != 0
            # get the center of the other ball
            ball_x = ball[:x] + (ball_diameter / 2)
            ball_y = ball[:y] + (ball_diameter / 2)
            distance_to_ball = ((ball_x - cueball_center_x) ** 2 + (ball_y - cueball_center_y) ** 2) ** (1 / 2)

            ball_unit_y = (cueball_center_y - ball_y) / distance_to_ball
            if ball_unit_y == 0
               sign_ball_y = 1 
            else
                sign_ball_y = ball_unit_y / ball_unit_y.abs()
            end

            if sign_ball_y == sign_unit_y
                b = -2 * (ball_y + (slope * (ball_x - x_int)))
                c = (ball_y ** 2)  + ((ball_x - x_int) ** 2) - ball_diameter_sqrd
                discriminant = (b ** 2) - (4 * a * c)
                if discriminant >= 0
                    # ball[:path] = "sprites/highlighted_pocket.png"

                    # assign here so that x and y are truly x and y
                    guide_y1 = (-b + (discriminant ** (1 / 2))) / (2 * a)
                    guide_x1 = (slope * guide_y1) + x_int
                    distance1 = ((guide_x1 - cueball_center_x) ** 2 + (guide_y1 - cueball_center_y) ** 2)

                    guide_y2 = (-(discriminant ** (1 / 2)) - b) / (2 * a)
                    guide_x2 = (slope * guide_y2) + x_int
                    distance2 = ((guide_x2 - cueball_center_x) ** 2 + (guide_y2 - cueball_center_y) ** 2)

                    if distance1 < distance2
                        distance1 = distance1 ** (1 / 2)
                        if distance1 <= closest_dist
                            sign_guide_x = (cueball_center_x - guide_x1) / (cueball_center_x - guide_x1).abs()
                            sign_guide_y = (cueball_center_y - guide_y1) / (cueball_center_y - guide_y1).abs()
                            if sign_guide_y == sign_unit_y
                                closest_dist = distance1
                                closest_x = guide_x1
                                closest_y = guide_y1
                                closest_ball_x = ball_x
                                closest_ball_y = ball_y
                            end
                        end
                    else
                        distance2 = distance2 ** (1 / 2)
                        if distance2 <= closest_dist
                            sign_guide_x = (cueball_center_x - guide_x2) / (cueball_center_x - guide_x2).abs()
                            sign_guide_y = (cueball_center_y - guide_y2) / (cueball_center_y - guide_y2).abs()
                            if sign_guide_y == sign_unit_y
                                closest_dist = distance2
                                closest_x = guide_x2
                                closest_y = guide_y2
                                closest_ball_x = ball_x
                                closest_ball_y = ball_y
                            end
                        end
                    end
                # else
                    # ball[:path] = "sprites/ball2.png"
                end
            # else
                # ball[:path] = "sprites/ball1.png"
            end
        end
    end

    ball_radius = ball_diameter / 2
    left = args.state.tableleft
    right = args.state.tableright
    bottom = args.state.tablebottom
    top = args.state.tabletop

    if closest_x
        if !(closest_x > left + ball_radius && closest_x < right - ball_radius && closest_y > bottom + ball_radius && closest_y < top - ball_radius)
            render_guide_at_border args, unit_x, unit_y, cueball_center_x, cueball_center_y, slope, y_int, ball_diameter, left, right, bottom, top
        else
            dist = (((closest_ball_x - closest_x) ** 2) - ((closest_ball_y - closest_y) ** 2)) ** (1 / 2)
            nuvx = (closest_ball_x - closest_x) / dist
            nuvy = (closest_ball_y - closest_y) / dist

            guide_center_x = closest_x - (ball_diameter * nuvx)
            guide_center_y = closest_y - (ball_diameter * nuvy)
            # puts "x guide: #{guide_center_x} y guide: #{guide_center_y} nuvx: #{nuvx} nuvy: #{nuvy}"

            # as you can see, closest_x is the issue. closest_ball_x isn't the right ball, but at least it makes sense
            args.outputs.lines << [cueball_center_x, cueball_center_y, closest_x, closest_y + (ball_diameter / 2 * sign_unit_y)]
            # args.outputs.lines << [cueball_center_x, cueball_center_y, closest_ball_x, closest_ball_y, 0 , 0, 255]
            args.outputs.sprites << [closest_x - (ball_diameter / 2), closest_y - (ball_diameter / 2), ball_diameter, ball_diameter, "sprites/guide_ball.png"]
        end
    else
        if unit_y > 0
            args.outputs.lines << [cueball_center_x, cueball_center_y, cueball_center_x, args.state.tablebottom + ball_diameter]
            args.outputs.sprites << [cueball_center_x - (ball_diameter / 2), args.state.tablebottom, ball_diameter, ball_diameter, "sprites/guide_ball.png"]
        else
            if unit_y != 0
                args.outputs.lines << [cueball_center_x, cueball_center_y, cueball_center_x, args.state.tabletop - ball_diameter]
                args.outputs.sprites << [cueball_center_x - (ball_diameter / 2), args.state.tabletop - ball_diameter, ball_diameter, ball_diameter, "sprites/guide_ball.png"]
            end
        end
    end

end

def render_guide_at_border args, unit_x, unit_y, cueball_center_x, cueball_center_y, slope, y_int, ball_diameter, left, right, bottom, top

    if unit_x > 0
        guide_y = (slope * (left + (ball_diameter / 2))) + y_int
    else
        guide_y = (slope * (right - (ball_diameter / 2))) + y_int
    end

    if unit_y > 0
        guide_x = (bottom + (ball_diameter / 2) - y_int) / slope
    else
        guide_x = (top - (ball_diameter / 2) - y_int) / slope
    end

    x_offshift = (ball_diameter / 2) * unit_x
    y_offshift = (ball_diameter / 2) * unit_y

    if guide_x > left && guide_x < right
        if unit_y > 0
            args.outputs.lines << [cueball_center_x, cueball_center_y, guide_x + x_offshift, bottom + (ball_diameter / 2) + y_offshift]
            args.outputs.sprites << [guide_x - (ball_diameter / 2), bottom, ball_diameter, ball_diameter, "sprites/guide_ball.png"]
        else
            args.outputs.lines << [cueball_center_x, cueball_center_y, guide_x + x_offshift, top - (ball_diameter / 2) + y_offshift]
            args.outputs.sprites << [guide_x - (ball_diameter / 2), top - ball_diameter, ball_diameter, ball_diameter, "sprites/guide_ball.png"]
        end
    else
        if unit_x > 0
            args.outputs.lines << [cueball_center_x, cueball_center_y, left + (ball_diameter / 2) + x_offshift, guide_y + y_offshift]
            args.outputs.sprites << [left, guide_y - (ball_diameter / 2), ball_diameter, ball_diameter, "sprites/guide_ball.png"]
        else
            args.outputs.lines << [cueball_center_x, cueball_center_y, right - (ball_diameter / 2) + x_offshift, guide_y + y_offshift]
            args.outputs.sprites << [right - ball_diameter, guide_y - (ball_diameter / 2), ball_diameter, ball_diameter, "sprites/guide_ball.png"]
        end
    end
end




# before groupings set, render the balls that have been pocketed
def render_waiting_balls args
    args.outputs.labels << [450, 40, "pocketed balls: "]
    pocketed_balls = args.state.pocketed_balls
    ball_diameter = args.state.ball_diameter
    # puts "#{pocketed_balls[0][0]}"

    # solids
    pocketed_balls[0].each_with_index do |ball, n|
        args.outputs.sprites << [600 + (n * ball_diameter), 40 - (3 * ball_diameter / 4), ball_diameter, ball_diameter, ball[:path]]
    end
    
    # stripes
    pocketed_balls[1].each_with_index do |ball ,n|
        args.outputs.sprites << [600 + (7 * ball_diameter) + (n * ball_diameter), 40 - (3 * ball_diameter / 4), ball_diameter, ball_diameter, ball[:path]]
    end
end


# render all the pool stuff with transparency while in pause menu
def render_in_background args
    # pool table
    args.outputs.solids << [args.state.tableleft, args.state.tablebottom, args.state.table_width, args.state.table_height, 0, 150, 0, 180]

    # pockets
    args.state.pockets.each do |pocket|
        args.outputs.sprites << [pocket[0], pocket[1], pocket[2], pocket[3], pocket[4], 0, 180]
    end
end

#--------------------------------------------------------------------------------------------------------------------------------------------------
# updating balls stuff

# move the balls, see if they're pocketed, resolve border collision, apply friction, limit velocity
def update_balls args
    args.state.balls.each do |ball|
        ball[:x] = ball[:x] + ball[:velX]
        ball[:y] = ball[:y] + ball[:velY]
        pocketed? args, ball
        balls_border args, ball
    end
    friction args
    limit_vel args
end

# check if the ball is in any of the pockets
def pocketed? args, ball
    ball_center_x = ball[:x] + args.state.ball_diameter / 2
    ball_center_y = ball[:y] + args.state.ball_diameter / 2
    pocket_radius = args.state.pocket_diameter / 2
    args.state.pockets.each do |pocket|
        # add pocket radius to get to the cetner of the pocket
        dist = (((ball_center_x - (pocket[0] + pocket_radius)) ** 2) + ((ball_center_y - (pocket[1] + pocket_radius)) ** 2)) ** (1/2)
        if dist < pocket_radius
            case ball[:type]

            # if eight ball pocketed, win if the player pocketed all other balls
            when 8
                args.state.player1_type ||= 0
                # get the player's type
                if args.state.player == 0
                    player_type = args.state.player1_type
                else
                    player_type = 1 - args.state.player1_type
                end
                # if all of the player's group have been pocketed, win. Otherwise lose and reset.
                if player_type == 0 && args.state.pocketed_solids == 7
                    args.state.won = true
                elsif player_type == 1 && args.state.pocketed_stripes == 7
                    args.state.won = true
                else
                    reset args
                end

            # if cueball pocketed, scratch and set it invisible    
            when "cueball"
                if args.state.movement_mode != "scratch"
                    args.state.movement_mode = "scratch"
                    cueball = args.state.cueball
                    cueball[:velX] = 0
                    cueball[:velY] = 0
                    cueball[:path] = "sprites/invisible.png"
                end
            
            # otherwise, it's a stripe or solid, so put it in the list of balls pocketed this turn.
            # if it was the called ball and pocket, this was a successful call
            else
                args.state.sunk = true
                args.state.pocketed_this_turn << ball
                args.state.balls.delete(ball)
                if args.state.called_shot
                    called_pocket = args.state.called_pocket[0] == pocket[0] && args.state.called_pocket[1] == pocket[1]
                    called_ball = args.state.called_ball[0] == ball[:ball_number]
                    if called_ball && called_pocket
                        args.state.successful_call = true
                        args.state.called_pocket[4] = "sprites/pocket.png"
                        ball[:path] = "sprites/ball#{args.state.called_ball[0]}.png"
                    end
                end
            end
        end
    end
end

def friction args
    args.state.balls.each do |ball|
        ball[:velX] = ball[:velX] * args.state.friction_multiplier
        ball[:velY] = ball[:velY] * args.state.friction_multiplier

        # zero out velocity if it's low enough, it is not zeroed out, we know that there is something still moving
        # exclude the cueball in scratch though
        if ball[:velY].abs() < 0.1 && ball[:velX].abs() < 0.1
            ball[:velY] = 0
            ball[:velX] = 0
            if ball[:type] == "cueball" && args.state.movement_mode == "shot"
                ball[:path] = "sprites/cueball.png"
            end
        elsif ball[:type] == "cueball" && args.state.movement_mode == "scratch"
            0 == 0
        else
            args.state.still_moving = true
        end
    end
end

def limit_vel args
    args.state.balls.each do |ball|
        #absolute value of balls
        absolute_velX = ball[:velX].abs()
        absolute_velY = ball[:velY].abs()

        # if ball is faster than speedcap, set its vel to speed cap and apply correct sign
        if args.state.speedcap < absolute_velX && absolute_velX != 0
            ball[:velX] = args.state.speedcap * (ball[:velX] / absolute_velX)
        end

        if args.state.speedcap < absolute_velY  && absolute_velY != 0
            ball[:velY] = args.state.speedcap * (ball[:velY] / absolute_velY)
        end
    end
end

# ------------------------------------------------------------------------------------------------------------------
# collision stuff

def balls_border args, ball
    # x collision
    if ball[:x] < args.state.tableleft
        ball[:x] = args.state.tableleft
        ball[:velX] = -1 * (ball[:velX] * args.state.bumpSlow)
        args.state.border_bumped = true
    end
    
    if ball[:x] > args.state.tableright - args.state.ball_diameter
        ball[:x] = args.state.tableright - args.state.ball_diameter
        ball[:velX] = -1 * (ball[:velX] * args.state.bumpSlow)
        args.state.border_bumped = true
    end

    # y collision
    if ball[:y] < args.state.tablebottom
        ball[:y] = args.state.tablebottom
        ball[:velY] = -1 * (ball[:velY] * args.state.bumpSlow)
        args.state.border_bumped = true
    end

    if ball[:y] > args.state.tabletop - args.state.ball_diameter
        ball[:y] = args.state.tabletop - args.state.ball_diameter
        ball[:velY] = -1 * (ball[:velY] * args.state.bumpSlow)
        args.state.border_bumped = true
    end
end

#ball to ball collision
def collisions args
    num_balls = args.state.balls.length
    if num_balls > 1
        (0..num_balls - 1).each do |i|
            ball1 = args.state.balls[i]
            ((i + 1)..num_balls - 1).each do |j|
                ball2 = args.state.balls[j]
                dist = (((ball1[:x] - ball2[:x]) ** 2) + ((ball1[:y] - ball2[:y]) ** 2)) ** (1/2)
                if dist < args.state.ball_diameter
                    args.state.collision_data = resolve_bump ball1, ball2, dist, args
                    if i == 0 and args.state.first_collision_type == 3
                        args.state.first_collision_type = ball2[:type]
                    end
                    args.state.balls_collided = true
                end
            end
        end
    end
end

def resolve_bump ball1, ball2, dist, args
    #used for debug
    current_ball1_x = ball1[:x]
    current_ball1_y = ball1[:y]
    vel_x1 = ball1[:velX]
    vel_y1 = ball1[:velY]

    current_ball2_x = ball2[:x]
    current_ball2_y = ball2[:y]
    vel_x2 = ball2[:velX]
    vel_y2 = ball2[:velY]

    # adjustment (if the are moving with the exact same velocities, "a" will get messed up)
    if vel_x2 != vel_x1 && vel_y2 != vel_y1
        vel_x_diff = vel_x2 - vel_x1
        vel_y_diff = vel_y2 - vel_y1
        pos_x_diff = current_ball2_x - current_ball1_x
        pos_y_diff = current_ball2_y - current_ball1_y

        a = (vel_x_diff ** 2) + (vel_y_diff ** 2)
        b = 2 * ((vel_x_diff * pos_x_diff) + (vel_y_diff * pos_y_diff))
        c = (pos_x_diff ** 2) + (pos_y_diff ** 2) - (args.state.ball_diameter ** 2)
        discriminant = (b ** 2) - (4 * a * c)
        if discriminant >=0
            time_shift1 = ((discriminant ** (1 / 2)) - b) / (2 * a)
            time_shift2 = (-(discriminant ** (1 / 2)) - b) / (2 * a)
            if time_shift1 < 0
                new_ball1_x = current_ball1_x + (time_shift1 * vel_x1)
                new_ball1_y = current_ball1_y + (time_shift1 * vel_y1)

                new_ball2_x = current_ball2_x + (time_shift1 * vel_x2)
                new_ball2_y = current_ball2_y + (time_shift1 * vel_y2)
            elsif time_shift2 < 0
                new_ball1_x = current_ball1_x + (time_shift2 * vel_x1)
                new_ball1_y = current_ball1_y + (time_shift2 * vel_y1)

                new_ball2_x = current_ball2_x + (time_shift2 * vel_x2)
                new_ball2_y = current_ball2_y + (time_shift2 * vel_y2)
            end
        else
            new_ball1_x = current_ball1_x
            new_ball1_y = current_ball1_y

            new_ball2_x = current_ball2_x
            new_ball2_y = current_ball2_y
        end
    else
        new_ball1_x = current_ball1_x
        new_ball1_y = current_ball1_y

        new_ball2_x = current_ball2_x
        new_ball2_y = current_ball2_y
    end

    distance = (((new_ball1_x - new_ball2_x) ** 2) + ((new_ball1_y - new_ball2_y) ** 2)) ** (1 / 2)
    #normal unit vector
    nuvx = (new_ball2_x - new_ball1_x) / distance
    nuvy = (new_ball2_y - new_ball1_y) / distance

    #tangent unit vector
    tuvx = -nuvy
    tuvy = nuvx

    #initial projected velocity vectors (normal and tangent) (really magnitudes of the vectors)
    v1ni = (ball1[:velX] * nuvx) + (ball1[:velY] * nuvy)
    v1ti = (ball1[:velX] * tuvx) + (ball1[:velY] * tuvy)

    v2ni = (ball2[:velX] * nuvx) + (ball2[:velY] * nuvy)
    v2ti = (ball2[:velX] * tuvx) + (ball2[:velY] * tuvy)

    #final normal vectors
    mass1 = ball1[:mass]
    mass2 = ball2[:mass]
    v1nf = ((v1ni * (mass1 - mass2)) + (2 * mass2 * v2ni)) / (mass1 + mass2)
    v2nf = ((v2ni * (mass2 - mass1)) + (2 * mass1 * v1ni)) / (mass1 + mass2)
    
    #turn the magnitudes calculated into vectors (final tangent magnitudes = initial tangent magnitudes)
    v1nfx = v1nf * nuvx
    v1nfy = v1nf * nuvy
    v1tfx = v1ti * tuvx
    v1tfy = v1ti * tuvy

    v2nfx = v2nf * nuvx
    v2nfy = v2nf * nuvy
    v2tfx = v2ti * tuvx
    v2tfy = v2ti * tuvy

    
    #convert from normal and tangent to regular velocity
    v1fx = v1nfx + v1tfx
    v1fy = v1nfy + v1tfy
    v2fx = v2nfx + v2tfx
    v2fy = v2nfy + v2tfy

    # ball1[:velX] = 0
    # ball1[:velY] = 0

    # ball2[:velX] = 0
    # ball2[:velY] = 0

    ball1[:velX] = v1nfx + v1tfx
    ball1[:velY] = v1nfy + v1tfy

    ball2[:velX] = v2nfx + v2tfx
    ball2[:velY] = v2nfy + v2tfy

    v1n_end = (ball1[:velX] * nuvx) + (ball1[:velY] * nuvy)
    v1t_end = (ball1[:velX] * tuvx) + (ball1[:velY] * tuvy)

    v2n_end = (ball2[:velX] * nuvx) + (ball2[:velY] * nuvy)
    v2t_end = (ball2[:velX] * tuvx) + (ball2[:velY] * tuvy)

    if (v1n_end + v2n_end - v1ni - v2ni).abs() > 0.01
        puts "you blew it!"
    end
    if (v1t_end + v2t_end - v1ti - v2ti).abs() > 0.01
        puts "you suck!"
    end

    return [nuvx, nuvy, tuvx, tuvy, ball1[:x], ball1[:y], ball2[:x], ball2[:y], v1ni, v1ti, v2ni, v2ti, v1fx, v1fy, v2fx, v2fy]
end

# ball to ball collision without cueball
def walking_collisions args
    num_balls = args.state.balls.length
    if num_balls > 1
        (0..num_balls - 1).each do |i|
            if i != 0
                ball1 = args.state.balls[i]
                ((i + 1)..num_balls - 1).each do |j|
                    ball2 = args.state.balls[j]
                    dist = (((ball1[:x] - ball2[:x]) ** 2) + ((ball1[:y] - ball2[:y]) ** 2)) ** (1/2)
                    if dist < args.state.ball_diameter
                        args.state.collision_data = resolve_bump ball1, ball2, dist, args
                        args.state.num_collisions += 1
                        args.state.balls_collided = true
                    end
                end
            end
        end
    end
end

# stop cueball from going past baulk line
def scratch_collision args
    # x collision
    ball = args.state.cueball
    baulk_line = args.state.tableleft + (args.state.table_width / 5) - args.state.ball_diameter
    if ball[:x] > baulk_line
        ball[:x] = baulk_line
        ball[:velX] = 0
    end
end

# ---------------------------------------------------------------------------------------------------------------
# end of turn or beginning of turn stuff

def new_turn args
    # only need to reset sprites if shot called (shot not called only on break)
    if !args.state.break
        reset_sprites args
    end
    # see if the first ball the cueball collided with is valid (after, set the first ball data to a nonsensical value)
    first_collision_good = first_collision args
    args.state.first_collision_type = 3
    count_pocketed_balls args, first_collision_good

    # set back to cue mode and reset face if not result of scratch <---- not sure why this || is here
    if !first_collision_good #|| (args.state.table_open && !args.state.sunk)
        args.state.movement_mode = "scratch"
        args.state.cueball[:x] = args.state.cueball_start_x
        args.state.cueball[:y] = args.state.cueball_start_y
        args.state.cueball[:velX] = 0
        args.state.cueball[:velY] = 0
    end

    # set to call mode unless the shot was a scratch 
    if !(args.state.movement_mode == "scratch")
        args.state.movement_mode = "cue"
        args.state.cueball[:path] = "sprites/cueball.png"
        args.state.called_shot = false
    # if it's a scratch, put the ball back on the table
    else
        cueball = args.state.cueball
        cueball[:x] = args.state.cueball_start_x
        cueball[:y] = args.state.cueball_start_y
        cueball[:path] = "sprites/cueball.png"
    end

    # switch players if ball not sunk on break, if unsucessful called shot, or if not collided with first 
    if (args.state.break && !args.state.sunk) || !args.state.successful_call || !first_collision_good
        args.state.player = (args.state.player + 1) % args.state.num_players
    end

    # if grouping not set, make player 1's type so that calling ball is always first solid
    if args.state.table_open
        if args.state.player == 0
            args.state.player1_type = 0
        else
            args.state.player1_type = 1
        end
    end

    # always happen after shot
    args.state.break = false
    args.state.angle_chosen = false
    args.state.angle_locked = false

end

def reset_sprites args
    #reset sprites
    #args.state.called_ball = [img_path, ball_hash]
    called_ball = args.state.called_ball
    called_ball[1][:path] = "sprites/ball#{called_ball[0]}.png"
    args.state.called_pocket[4] = "sprites/pocket.png"

    #reset the called variables (except called shot which is done in movement mode transition)
    args.state.end_of_called = false
    args.state.call_index = 0
end

def first_collision args
    # if all of the player's group have been pocketed, win. Otherwise lose and reset
    first_hit = args.state.first_collision_type
    if args.state.table_open
        player_type = 6
    else
        player_type = (args.state.player1_type - args.state.player).abs()
    end
    if first_hit == player_type
        return true
    elsif args.state.table_open
        if first_hit == 8
            return false
        else
            return true
        end
    elsif first_hit == 8
        if player_type == 0 && args.state.first_stripe == 1
            return true
        elsif player_type == 1 && args.state.balls[args.state.balls.length - 2][:type] != 1
            return
        end
    else
        return false
    end

end

def count_pocketed_balls args, first_collision_good
    args.state.pocketed_this_turn.each do |ball|
        type = ball[:type]
        index = (ball[:ball_number] - 1 - (8 * type)) % 7
        args.state.pocketed_balls[type][index] = ball

        # set ball groups if called ball made it in and ball groups not set
        if args.state.table_open && args.state.successful_call && first_collision_good #to be a successful call, it must not be the break
            if args.state.player == 0
                args.state.player1_type = args.state.called_ball[1][:type]
            else
                args.state.player1_type = 1 - args.state.called_ball[1][:type]
            end
            args.state.table_open = false
            args.state.type_set = true
        end

        if type  == 0
            args.state.pocketed_solids += 1
            args.state.first_stripe -= 1
        else
            args.state.pocketed_stripes += 1
        end
    end
    args.state.pocketed_this_turn = []
end

def reset args
    #reset cueball
    args.state.cueball[:x] = args.state.cueball_start_x
    args.state.cueball[:y] = args.state.cueball_start_y
    args.state.cueball[:velX] = 0
    args.state.cueball[:velY] = 0
    args.state.cueball[:path] = "sprites/cueball.png"

    #reset game state
    if !args.state.break && args.state.ball_chosen
        reset_sprites args
    end
    args.state.movement_mode = "scratch"
    args.state.balls = [args.state.cueball]
    args.state.player = rand(2)
    args.state.type_set = false
    args.state.table_open = true
    args.state.break = true
    args.state.called_shot = false
    args.state.called_ball = [0, 0]
    args.state.called_pocket = [0, 0, 0, 0, 0]
    args.state.successful_call = false
    args.state.angle_chosen = false
    args.state.angle_locked = false
    args.state.won = false

    # reset pocketed balls
    pocketed_balls = [[], []]
    7.times do |i|
        pocketed_balls[0] << {path: "sprites/guide_ball.png", ball_number: 0}
        pocketed_balls[1] << {path: "sprites/guide_ball.png", ball_number: 0}
    end
    args.state.pocketed_balls = pocketed_balls
    args.state.pocketed_stripes = 0
    args.state.pocketed_solids = 0

    #create new triangle
    args.state.colored_balls = [[1, 2, 3, 4, 5, 6, 7], [9, 10, 11, 12, 13, 14, 15]]
    create_triangle args
end

# -------------------------------------------------------------------------------------------------------------------
# dev commands

#commands to add new balls and reset
def dev_commands args
    if args.inputs.keyboard.key_down.m || args.inputs.controller_one.key_down.a
        new_ball args
    end

    # commented out because breaks game (type = "h")
    # if args.inputs.keyboard.key_down.h || args.inputs.controller_one.key_down.b
    #     heavy_ball args
    # end

    if args.inputs.keyboard.key_down.one || args.inputs.controller_one.key_down.x
        new_ball1 args
    end

    if args.inputs.keyboard.key_down.two || args.inputs.controller_one.key_down.y
        new_ball2 args
    end

    if args.inputs.keyboard.key_down.r || args.inputs.controller_one.key_down.start
        reset args
    end
end

#create new 8ball
def new_ball args
    args.state.balls << {x: (args.state.tableright - args.state.ball_diameter - args.state.tableleft).randomize(:ratio) + args.state.tableleft,
                        y: (args.state.tabletop - args.state.ball_diameter - args.state.tablebottom).randomize(:ratio) + args.state.tablebottom,
                        velX: 13.randomize(:ratio, :sign),
                        velY: 13.randomize(:ratio, :sign),
                        path: "sprites/ball8.png",
                        mass: args.state.ball_weight,
                        type: 8
                        }
end

#create new 1ball
def new_ball1 args
    args.state.balls << {x: 200,
                        y: 250,
                        velX: 0,
                        velY: 0,
                        path: "sprites/ball1.png",
                        mass: args.state.ball_weight,
                        type: 1,
                        ball_number: 1
                        }
    # args.state.balls << {x: (args.state.tableright - args.state.ball_diameter - args.state.tableleft).randomize(:ratio) + args.state.tableleft,
    #                     y: (args.state.tabletop - args.state.ball_diameter - args.state.tablebottom).randomize(:ratio) + args.state.tablebottom,
    #                     velX: -13,
    #                     velY: -13,
    #                     path: "sprites/ball0.png",
    #                     mass: args.state.ball_weight,
    #                     type: 0
    #                     }
end

#create new 2ball
def new_ball2 args
    args.state.balls << {x: 200 - ((10 / (200 ** (1 / 2))) * args.state.ball_diameter) + 30,
                        y: 250 + ((-10 / (200 ** (1 / 2))) * args.state.ball_diameter) + 2 - 30,
                        velX: -10,
                        velY: 10,
                        path: "sprites/ball2.png",
                        mass: args.state.ball_weight,
                        type: 2,
                        ball_number: 2
                        }
    # args.state.balls << {x: (args.state.tableright - args.state.ball_diameter - args.state.tableleft).randomize(:ratio) + args.state.tableleft,
    #                     y: (args.state.tabletop - args.state.ball_diameter - args.state.tablebottom).randomize(:ratio) + args.state.tablebottom,
    #                     velX: 13,
    #                     velY: 13,
    #                     path: "sprites/ball1.png",
    #                     mass: args.state.ball_weight,
    #                     type: 1
    #                     }
end

#create new heavy ball
def heavy_ball args
    args.state.balls << {x: (args.state.tableright - args.state.ball_diameter - args.state.tableleft).randomize(:ratio) + args.state.tableleft,
                        y: (args.state.tabletop - args.state.ball_diameter - args.state.tablebottom).randomize(:ratio) + args.state.tablebottom,
                        velX: 13,
                        velY: 13,
                        path: "sprites/heavy.png",
                        mass: args.state.ball_weight + 2,
                        type: "heavy"
                        }
end


#-----------------------------------------------------------------------------------------------------

#for bug testing when cueball was not in balls
#add this to initiate: args.state.collision_data ||= []
# def render_ball_data args
#     ball1 = args.state.balls[0]
#     ball2 = args.state.balls[1]
#     collision_data = args.state.collision_data

#     dist = (((ball1[:x] - ball2[:x]) ** 2) + ((ball1[:y] - ball2[:y]) ** 2)) ** (1/2)
#     args.outputs.labels << [100, 120, "dist: #{dist}"]
#     args.outputs.labels << [100, 170, "ball1: (#{ball1[:x]}, #{ball1[:y]}, #{ball1[:velX]}, #{ball1[:velY]}"]
#     args.outputs.labels << [100, 150, "ball2: (#{ball2[:x]}, #{ball2[:y]}, #{ball2[:velX]}, #{ball2[:velY]}"]
#     args.outputs.labels << [100, 80,  "new_dist: #{collision_data[10]}"]
#     args.outputs.labels << [100, 60, "ball1 finalx: #{collision_data[15]}  finaly: #{collision_data[16]}"]
#     args.outputs.labels << [100, 40, "ball2 finalx: #{collision_data[17]}  finaly: #{collision_data[18]}"]
# end




# -----------------------------------------------------------------------------------------------------------------------------------------
# outdated stuff

## old ball_collision movement method
    # #normal unit vector
    # nuvx = (ball2[:x] - ball1[:x]) / dist
    # nuvy = (ball2[:y] - ball1[:y]) / dist

    # #tangent unit vector
    # tuvx = -nuvy
    # tuvy = nuvx

    # #find minimum translation distance (the distance to move the balls so they are just barely touching)
    # mtdx = nuvx * (args.state.ball_diameter + 0.5 - dist)
    # mtdy = nuvy * (args.state.ball_diameter + 0.5 - dist)

    # #find the mtd for each ball
    # mtdx = mtdx / 2
    # mtdy = mtdy / 2


    # #push/pull balls according to mtd
    # ball1[:x] = ball1[:x] - mtdx
    # ball1[:y] = ball1[:y] - mtdy

    # ball2[:x] = ball2[:x] + mtdx
    # ball2[:y] = ball2[:y] + mtdy
    # new_dist = (((ball1[:x] - ball2[:x]) ** 2) + ((ball1[:y] - ball2[:y]) ** 2)) ** (1/2)