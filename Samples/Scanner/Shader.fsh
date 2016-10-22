//
//  Shader.fsh
//  testES
//
//  Created by 田中翔吾 on 2015/11/24.
//  Copyright © 2015年 田中翔吾. All rights reserved.
//

varying lowp vec4 colorVarying;

void main()
{
    gl_FragColor = colorVarying;
}
