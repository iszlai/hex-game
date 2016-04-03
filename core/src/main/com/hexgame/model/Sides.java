package com.hexgame.model;

/**
 * Created by leheli on 2016.03.19..
 */
public enum Sides {
    SIDE_A('A'),
    SIDE_B('B'),
    SIDE_C('C'),
    SIDE_D('D'),
    SIDE_E('E'),
    SIDE_F('F');

    public final String textureFile;

    Sides(Character c){
        this.textureFile="hex_"+c+".png";
    }
}
