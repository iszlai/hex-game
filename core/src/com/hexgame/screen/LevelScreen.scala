package com.hexgame.screen

import com.badlogic.gdx.utils.Timer
import com.badlogic.gdx.{Gdx, Screen}
import com.badlogic.gdx.graphics.{GL20, Color, Texture}
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.hexgame.Hex
import com.hexgame.helper.HexHelper
import com.hexgame.model.{Deck, GameObject, GridLocation, HiveGrid}

/**
  * Created by leheli on 2016.08.01..
  */
class LevelScreen(app: Hex, lvl: Int = 0) extends Screen {

  val batch = new SpriteBatch
  val img = new Texture("hex.png")
  val row = new HiveGrid(5, img, lvl)
  val hex = new Deck()
  hex.setX(1000)
  System.out.println(Gdx.graphics.getWidth)
  System.out.println(Gdx.graphics.getHeight)


  private def update {
    if (Gdx.input.justTouched) {
      val x: Float = Gdx.input.getX
      val y: Float = Gdx.graphics.getHeight - Gdx.input.getY

      import scala.collection.JavaConversions._

      for (sprite <- row.list) {
        if (sprite.getBoundingRectangle.contains(x, y) && sprite.clickable) {
          sprite.clickable = false
          sprite.setColor(Color.RED)
          sprite.setTexture(hex.getTexture)
          val neighbour: GridLocation = sprite.location.getNeighbour(hex.side)
          val gameObject: GameObject = row.grid.get(neighbour)
          if (gameObject != null) {
            gameObject.setColor(Color.GREEN)
            gameObject.walkAble = true
          }
          hex.next
          if (HexHelper.isGameOver(row.start, row.end)) {
            Timer.schedule(new Timer.Task() {
              def run {
                app.setScreen(new StarsScreen(app, lvl + 1))
              }
            }, 1)
          }
        }
      }
    }
  }

  def show {
  }

  def render(delta: Float) {
    Gdx.gl.glClearColor(0.81f, 0.85f, 0.86f, 1)
    Gdx.gl.glClear(GL20.GL_COLOR_BUFFER_BIT)
    batch.begin
    row.draw(batch)
    hex.draw(batch)
    batch.end
    update
  }

  def resize(width: Int, height: Int) {
  }

  def pause {
  }

  def resume {
  }

  def hide {
  }

  def dispose {
    batch.dispose
    img.dispose
  }
}
